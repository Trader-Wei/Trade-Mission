# anya_trade_app

Flutter 製的合約交易任務看板 App，支援監控持倉、結算紀錄、K 線與未結盈虧統計。

## 功能概要

- **任務看板**：監控中 / 已結算分頁，列表顯示交易對、槓桿、ROI、進場時間、狀態
- **未結盈虧統計**：監控中分頁頂部顯示持倉合計未結盈虧（U）與持倉筆數
- **倉位詳情**：K 線圖（15m/1h/4h）、OI 變動、倉位摘要（開倉點位、倉位價值、Funding、PNL、ROI）
- **結算紀錄**：已結算僅顯示數據（基本／進場／出場／目標與結果／盈虧／來源／筆記），可編輯筆記
- **手動出場**：支援自訂出場價與比例；結算類型依盈虧顯示止盈/止損反饋
- **盈虧計算**：含手續費率（預設 0.055%，可於 API 設定自訂）
- **API 同步**：Binance / BingX / BitTap 合約持倉同步；BingX 補錄最近一天已平倉
- **網頁版**：需自訂 Proxy（如 Cloudflare Worker），見 `cloudflare-worker/`

## 啟動

```bash
flutter pub get
flutter run -d chrome   # 網頁
flutter run             # 預設裝置
```

## 建置網頁

```bash
flutter build web --base-href /anya_trade_app/
```

## GitHub Pages 部署

推送到 `main` 後，由 `.github/workflows/deploy-web.yml` 自動建置並部署網頁版。  
請於 Repo → Settings → Pages → Source 選擇 **GitHub Actions**。

## 專案結構

- `lib/main.dart` - 主程式（任務看板、詳情、設定、API、圖表）
- `cloudflare-worker/proxy.js` - 網頁版 CORS 代理（可部署至 Cloudflare Workers）
