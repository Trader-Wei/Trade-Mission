# 賓果賓果預言機

靜態網頁版，可從遠端開啟。

## 遠端網址

推送至 GitHub 後，若已啟用 GitHub Pages（Settings → Pages → Source: GitHub Actions），網址為：

**https://trader-wei.github.io/Trade-Mission/bingobingo/**

## 說明

- 「取得預測」：依內建 100 期資料計算 3 星／4 星推薦
- 「更新開獎號碼」：GitHub Pages 版無後端 API，會重新載入同目錄 recent_draws.json
- 若要一鍵更新＋ML 預測，請在本機或 EC2 啟動 `python -m bingobingo_bot.api_server`
