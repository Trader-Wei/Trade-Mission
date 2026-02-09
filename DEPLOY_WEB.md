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

### 5. 確認有部署到新 repo（改名後必做）

本機專案要「指到」新 repo 並推上去，GitHub Actions 才會在新 repo 跑、網站才會更新。

**步驟一：看現在指到哪個 repo**

在專案資料夾開終端機（PowerShell 或 CMD），執行：

```bash
git remote -v
```

會看到兩行，例如：  
`origin  https://github.com/舊帳號/舊倉庫名.git (fetch)`  
`origin  https://github.com/舊帳號/舊倉庫名.git (push)`

**步驟二：改成新 repo 網址**

把 `舊帳號`、`舊倉庫名` 換成你**現在**的 GitHub 帳號與倉庫名（例如 Trader-Wei、anya_trade_app）：

```bash
git remote set-url origin https://github.com/Trader-Wei/你的倉庫名.git
```

（請把 `Trader-Wei`、`你的倉庫名` 換成你實際的帳號與 repo 名稱。）

再執行一次 `git remote -v` 確認兩行都變成新網址。

**步驟三：推送到新 repo**

```bash
git push -u origin main
```

若新 repo 是空的或還沒設 main，第一次可能會要你設上游分支，照提示做即可。  
若出現權限錯誤，請到 GitHub 該 repo 確認你有 push 權限，或用 Personal Access Token 登入。

**步驟四：確認有部署**

1. 打開瀏覽器，到 **https://github.com/你的帳號/你的倉庫名**
2. 點上方 **Actions**，看有沒有「Deploy Web to GitHub Pages」在跑或已成功（綠色勾）
3. 到 **Settings → Pages**，Source 選 **GitHub Actions**（若還沒選）
4. 用新網址開網站：`https://你的帳號.github.io/你的倉庫名/`

之後只要在專案裡改完程式、`git add`、`git commit`、`git push origin main`，就會自動部署到這個新 repo 的網站。

---

### 6. 改名後網站沒更新？

- **改了 GitHub 使用者名稱**（例如改成 Trader-Wei）：  
  網址會變成 `https://Trader-Wei.github.io/倉庫名/`，請用**新網址**開；舊網址可能不會自動跳轉。
- **改了倉庫名稱**：  
  網址會變成 `https://你的帳號.github.io/新倉庫名/`，請用新網址。  
  本專案建置時會依「目前倉庫名」設路徑，所以改名後再 push 一次就會對應新網址。
- **確認有部署成功**：  
  先完成上面「5. 確認有部署到新 repo」；然後 Repo → **Actions** 看「Deploy Web to GitHub Pages」是否跑完；**Settings → Pages** 的 Source 是否為 **GitHub Actions**。  
  若剛改名，可到 Actions 點「Run workflow」手動觸發一次部署。

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
