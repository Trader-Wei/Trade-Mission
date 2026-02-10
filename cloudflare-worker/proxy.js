/**
 * Cloudflare Worker - CORS 代理（轉發認證 Header）
 * 用於網頁版 Flutter 應用呼叫交易所 API（需 API Key）
 *
 * 部署步驟：
 * 1. 登入 Cloudflare Dashboard -> Workers & Pages -> Create Worker
 * 2. 複製此腳本到編輯器
 * 3. Deploy
 * 4. 複製 Worker URL（如 https://xxx.workers.dev）到 App 的 Proxy 設定
 */
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  // CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Max-Age': '86400',
      },
    })
  }

  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  try {
    const body = await request.json()
    const { url, headers = {} } = body
    if (!url || typeof url !== 'string') {
      return jsonResponse({ error: 'Missing url' }, 400)
    }

    const res = await fetch(url, {
      method: 'GET',
      headers: headers,
    })

    const text = await res.text()
    return new Response(text, {
      status: res.status,
      statusText: res.statusText,
      headers: {
        'Content-Type': res.headers.get('Content-Type') || 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    })
  } catch (e) {
    return jsonResponse({ error: (e?.message || e)?.toString() || 'Unknown error' }, 500)
  }
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  })
}
