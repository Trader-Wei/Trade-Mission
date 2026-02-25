#!/usr/bin/env node
// OpenClaw ↔ Claude Code CLI Proxy
// Exposes OpenAI-compatible /v1/chat/completions endpoint
// Routes through: claude --print (optionally with --dangerously-skip-permissions for tools)

const express = require('express');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const PORT = parseInt(process.env.PORT || '3456', 10);
const API_KEY = process.env.API_KEY || '';
const CLAUDE_CLI = process.env.CLAUDE_CLI_PATH || 'claude';
const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT || '3', 10);
const REQUEST_TIMEOUT = parseInt(process.env.REQUEST_TIMEOUT || '300000', 10);

let activeRequests = 0;

const app = express();
app.use(express.json({ limit: '10mb' }));

// ---------------------------------------------------------------------------
// Auth middleware
// ---------------------------------------------------------------------------
function auth(req, res, next) {
  if (!API_KEY) return next();
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : header;
  if (token !== API_KEY) {
    return res.status(401).json({ error: { message: 'Invalid API key', type: 'auth_error' } });
  }
  next();
}

// ---------------------------------------------------------------------------
// Convert OpenAI messages array to a single prompt string
// ---------------------------------------------------------------------------
function messagesToPrompt(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return '';

  const parts = [];
  for (const msg of messages) {
    const role = msg.role || 'user';
    const content = typeof msg.content === 'string'
      ? msg.content
      : Array.isArray(msg.content)
        ? msg.content.map(c => c.text || '').join('\n')
        : String(msg.content || '');

    if (role === 'system') {
      parts.push(`[System Instructions]\n${content}\n[End System Instructions]`);
    } else if (role === 'assistant') {
      if (msg.tool_calls && Array.isArray(msg.tool_calls)) {
        const tcDesc = msg.tool_calls.map(tc => {
          let args = tc.function?.arguments || '{}';
          try { args = JSON.stringify(JSON.parse(args), null, 2); } catch (_) {}
          return `\n{"name": "${tc.function?.name}", "arguments": ${args}}\n`;
        }).join('\n');
        parts.push(`[Previous Assistant Response]\n${content || ''}${tcDesc ? '\n' + tcDesc : ''}`);
      } else {
        parts.push(`[Previous Assistant Response]\n${content}`);
      }
    } else if (role === 'tool') {
      const name = msg.name || msg.tool_call_id || 'unknown';
      parts.push(`[Tool Result: ${name}]\n${content}`);
    } else {
      parts.push(content);
    }
  }
  return parts.join('\n\n');
}

// ---------------------------------------------------------------------------
// Spawn Claude Code CLI and collect output
// ---------------------------------------------------------------------------
const MAX_TOOL_TURNS = parseInt(process.env.MAX_TOOL_TURNS || '10', 10);

function callClaude(prompt, systemPrompt, useTools = false) {
  return new Promise((resolve, reject) => {
    const args = ['--print'];

    if (useTools) {
      args.push('--dangerously-skip-permissions');
      args.push('--max-turns', String(MAX_TOOL_TURNS));
      args.push('--output-format', 'json');
    }

    const SYS_PROMPT_ARG_LIMIT = 100_000;
    let stdinInput = '';

    if (systemPrompt && systemPrompt.length <= SYS_PROMPT_ARG_LIMIT) {
      args.push('--system-prompt', systemPrompt);
    } else if (systemPrompt) {
      stdinInput += `[System Instructions]\n${systemPrompt}\n[End System Instructions]\n\n`;
    }

    stdinInput += prompt;

    const proc = spawn(CLAUDE_CLI, args, {
      cwd: process.env.HOME || '/home/ubuntu',
      env: { ...process.env },
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: REQUEST_TIMEOUT,
    });

    proc.stdin.write(stdinInput);
    proc.stdin.end();

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    proc.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

    proc.on('close', (code) => {
      if (code !== 0) {
        const errPreview = stderr.slice(0, 2000).trim() || '(no stderr)';
        console.error(`[Claude CLI stderr] ${errPreview}`);
        reject(new Error(`Claude CLI exited with code ${code}: ${stderr.slice(0, 500)}`));
      } else {
        let result = stdout.trim();
        if (useTools && result) {
          try {
            const json = JSON.parse(result);
            result = (json.result || result).trim();
          } catch (_) {}
        }
        resolve(result);
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to spawn Claude CLI: ${err.message}`));
    });

    setTimeout(() => {
      try { proc.kill('SIGTERM'); } catch (_) {}
      reject(new Error('Claude CLI timed out'));
    }, REQUEST_TIMEOUT + 5000);
  });
}

// ---------------------------------------------------------------------------
// POST /v1/chat/completions
// ---------------------------------------------------------------------------
app.post('/v1/chat/completions', auth, async (req, res) => {
  const { messages, model, stream, tools } = req.body;

  if (!messages || !Array.isArray(messages)) {
    return res.status(400).json({
      error: { message: 'messages array is required', type: 'invalid_request_error' }
    });
  }

  if (activeRequests >= MAX_CONCURRENT) {
    return res.status(429).json({
      error: { message: 'Too many concurrent requests, please retry later', type: 'rate_limit_error' }
    });
  }

  activeRequests++;
  const requestId = `chatcmpl-${randomUUID().replace(/-/g, '').slice(0, 24)}`;
  const created = Math.floor(Date.now() / 1000);

  let systemPrompt = '';
  const nonSystemMessages = [];
  for (const msg of messages) {
    if (msg.role === 'system') {
      systemPrompt += (systemPrompt ? '\n' : '') + (typeof msg.content === 'string' ? msg.content : '');
    } else {
      nonSystemMessages.push(msg);
    }
  }

  const hasTools = tools && Array.isArray(tools) && tools.length > 0;
  const prompt = messagesToPrompt(nonSystemMessages);

  console.log(`[${new Date().toISOString()}] Request ${requestId} | model=${model || 'default'} | stream=${!!stream} | native_tools=${hasTools} | messages=${messages.length}`);

  try {
    const result = await callClaude(prompt, systemPrompt || undefined, hasTools);

    if (stream) {
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Request-Id', requestId);

      res.write(`data: ${JSON.stringify({
        id: requestId,
        object: 'chat.completion.chunk',
        created,
        model: model || 'claude-opus-4-6',
        choices: [{ index: 0, delta: { role: 'assistant', content: result }, finish_reason: null }],
      })}\n\n`);

      res.write(`data: ${JSON.stringify({
        id: requestId,
        object: 'chat.completion.chunk',
        created,
        model: model || 'claude-opus-4-6',
        choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
      })}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    } else {
      res.json({
        id: requestId,
        object: 'chat.completion',
        created,
        model: model || 'claude-opus-4-6',
        choices: [{
          index: 0,
          message: { role: 'assistant', content: result },
          finish_reason: 'stop',
        }],
        usage: {
          prompt_tokens: Math.ceil(prompt.length / 4),
          completion_tokens: Math.ceil(result.length / 4),
          total_tokens: Math.ceil((prompt.length + result.length) / 4),
        },
      });
    }

    activeRequests--;
    console.log(`[${new Date().toISOString()}] Completed ${requestId} | response_len=${result.length}`);
  } catch (err) {
    activeRequests--;
    console.error(`[${new Date().toISOString()}] Error ${requestId}:`, err.message);
    res.status(500).json({
      error: { message: err.message, type: 'server_error' }
    });
  }
});

// ---------------------------------------------------------------------------
// GET /v1/models
// ---------------------------------------------------------------------------
app.get('/v1/models', auth, (req, res) => {
  res.json({
    object: 'list',
    data: [
      { id: 'claude-opus-4-6', object: 'model', created: 1700000000, owned_by: 'anthropic' },
      { id: 'claude-sonnet-4-5-20250929', object: 'model', created: 1700000000, owned_by: 'anthropic' },
      { id: 'claude-haiku-4-5-20251001', object: 'model', created: 1700000000, owned_by: 'anthropic' },
    ],
  });
});

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------
app.get('/health', (req, res) => {
  res.json({ status: 'ok', active_requests: activeRequests, max_concurrent: MAX_CONCURRENT });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
app.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔══════════════════════════════════════════════╗
║ OpenClaw ↔ Claude Code Proxy                 ║
║ Port: ${String(PORT).padEnd(38)}║
║ Auth: ${(API_KEY ? 'Enabled' : 'Disabled (set API_KEY)').padEnd(38)}║
║ Max concurrent: ${String(MAX_CONCURRENT).padEnd(27)}║
║ Max tool turns: ${String(MAX_TOOL_TURNS).padEnd(26)}║
║ CLI: ${CLAUDE_CLI.padEnd(39)}║
╠══════════════════════════════════════════════╣
║ POST /v1/chat/completions                    ║
║ GET /v1/models                               ║
║ GET /health                                  ║
╚══════════════════════════════════════════════╝
`);
});
