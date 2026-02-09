# 網頁版部署說明（iPhone / 任何裝置直接用瀏覽器開）

## 方式一：GitHub Pages（推薦，有網址可長期用）

### 1. 把專案推到 GitHub

- 若還沒有 GitHub 帳號：到 [github.com](https://github.com) 註冊。
- 在 GitHub 上 **New repository**，名稱可填 `anya_trade_app`（或自訂，會影響網址）。
- 在本機專案目錄執行（請把 `你的帳號`、`anya_trade_app` 換成你的）：

```bash
git init
git add .
git commit -m "Deploy web"
git branch -M main
git remote add origin https://github.com/你的帳號/anya_trade_app.git
git push -u origin main
```

### 2. 開啟 GitHub Pages

- 進到該 Repo → **Settings** → 左側 **Pages**。
- **Build and deployment** 底下 **Source** 選 **GitHub Actions**。
- 儲存後，每次推送到 `main` 會自動建置並部署。

### 3. 等第一次跑完

- 到 Repo 的 **Actions** 分頁，看到 **Deploy Web to GitHub Pages** 跑完變綠色。
- 再回 **Settings → Pages**，上方會出現網址，例如：  
  `https://你的帳號.github.io/anya_trade_app/`

### 4. 在 iPhone 使用

- Safari 打開上面那個網址。
- 可點「分享」→「加入主畫面」，之後像 App 一樣從主畫面開啟。

---

## 方式二：Netlify Drop（不用 Git，最快）

1. 在本機專案目錄執行一次：`flutter build web`
2. 打開 [https://app.netlify.com/drop](https://app.netlify.com/drop)
3. 把資料夾 **`build\web`**（整個資料夾拖進去）拖到網頁上傳
4. 會得到一個隨機網址（例如 `https://xxxx.netlify.app`），用 Safari 開即可

注意：資料會存在「該裝置的瀏覽器」裡，換裝置或清除網站資料就沒了。

---

## 本機已建置好的檔案

你現在專案裡已經有 **`build/web`** 資料夾（剛建置好的），若選 Netlify Drop，直接拖這個資料夾即可。若選 GitHub Pages，只要把專案 push 上去並照上面開啟 Pages 即可。
