# 網頁版 API 代理（Cloudflare Worker）

網頁版因瀏覽器 CORS 限制，無法直接請求需認證的交易所 API。此 Worker 可轉發請求並帶上 API Key 等 Header。

## 部署步驟

1. 登入 [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. 左側選單進入 **Compute & AI** → **Workers & Pages**
3. 點選右上角藍色按鈕 **Create application**
4. 選擇 **Create Worker**（或預設建立 Worker 的選項）
5. 輸入 Worker 名稱後建立，進入 **Edit code**，將 `proxy.js` 內容貼上
6. 點 **Deploy** 部署
7. 複製 Worker URL（如 `https://your-worker.william122990.workers.dev`）
8. 在 App 的 API 設定中，將此 URL 填於 **Proxy URL** 欄位

## API 格式

Worker 接受 POST 請求，body 為 JSON：

```json
{
  "url": "https://fapi.binance.com/fapi/v2/positionRisk?timestamp=xxx&signature=xxx",
  "headers": {
    "X-MBX-APIKEY": "your_api_key"
  }
}
```

Worker 會代為請求該 URL 並帶上 headers，回傳目標 API 的響應。
