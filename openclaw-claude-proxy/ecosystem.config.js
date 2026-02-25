// PM2 process manager config
// Usage: pm2 start ecosystem.config.js
// 從此檔案所在目錄讀 .env，確保 PM2 從任何路徑啟動都能載入

const path = require('path');
const fs = require('fs');
const envPath = path.join(__dirname, '.env');
const dotenv = fs.existsSync(envPath)
  ? Object.fromEntries(
      fs.readFileSync(envPath, 'utf8')
        .split('\n')
        .filter(l => l.trim() && !l.startsWith('#'))
        .map(l => {
          const idx = l.indexOf('=');
          if (idx <= 0) return [];
          const k = l.slice(0, idx).trim();
          const v = l.slice(idx + 1).trim().replace(/^["']|["']$/g, '');
          return [k, v];
        })
        .filter(([k]) => k)
    )
  : {};

module.exports = {
  apps: [{
    name: 'openclaw-claude-proxy',
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '256M',
    env: {
      NODE_ENV: 'production',
      ...dotenv,
    },
  }],
};
