# 賓果賓果預測 Bot

使用 **隨機森林（Random Forest）**、**XGBoost** 與 **馬可夫鏈（Markov Chain）** 三種方法，預測台灣賓果賓果（BINGO BINGO）**最容易出現的 3 個號碼**（或當期 20 個號碼／超級獎號）。

## 賓果賓果規則簡述

- 號碼範圍：01～80  
- 每期開出：20 個不重複號碼 + 1 個超級獎號  
- 本 bot 預測「當期」主獎 20 個號碼（與超級獎號選填）

## 安裝

```bash
cd bingobingo_predictor
pip install -r requirements.txt
```

## 使用方式

### 1. 使用模擬歷史資料（示範）

未提供 CSV 時會自動產生模擬開獎資料並訓練：

```bash
# 在專案根目錄 anya_trade_app 下
python -m bingobingo_predictor.run_bot
```

或進入目錄後：

```bash
cd bingobingo_predictor
python run_bot.py
```

### 2. 使用自有歷史開獎 CSV

請從 [台灣彩券賓果賓果](https://www.taiwanlottery.com/lotto/result/bingo_bingo/) 下載或自行整理歷史開獎，CSV 格式範例：

- 第一欄：期別（可選）
- 其餘 20 欄：該期 20 個開獎號碼（欄位名可為 `n1`～`n20` 或 `1`～`20` 等）

```bash
python -m bingobingo_predictor.run_bot --csv 路徑/歷史開獎.csv
```

### 3. 參數說明

| 參數 | 說明 | 預設 |
|------|------|------|
| `--csv` | 歷史開獎 CSV 路徑 | 無（改用模擬資料） |
| `--top` | **只輸出最容易出現的 N 個號碼**（例如 3） | 無（輸出 20 個） |
| `--lookback` | 特徵回溯期數 | 100 |
| `--draws` | 模擬資料期數（僅在未給 `--csv` 時） | 500 |
| `--seed` | 模擬資料亂數種子 | 42 |
| `--super` | 一併輸出超級獎號預測 | 否 |

範例：加大回溯期數、並輸出超級獎號

```bash
python -m bingobingo_predictor.run_bot --csv history.csv --lookback 150 --super
```

## 方法簡介

1. **隨機森林**：以「近期出現頻率、距上次出現間隔、上期是否出現」等特徵，預測每個號碼在當期是否開出。  
2. **XGBoost**：同上特徵，以梯度提升樹再做一份機率預測。  
3. **馬可夫鏈**：依「上期該號是否有開出」估計「本期該號開出」的轉移機率。  

三者對 1～80 每個號碼各輸出一個「出現機率」，加權平均後取機率最高的 20 個號碼作為當期預測。

## 程式結構

- `data_loader.py`：CSV 載入、轉成 0/1 矩陣、特徵工程（頻率、間隔、上期狀態等）。  
- `markov_model.py`：馬可夫鏈轉移機率擬合與預測。  
- `models.py`：Random Forest 與 XGBoost 的訓練與機率輸出。  
- `predictor.py`：整合三模型、加權、輸出當期 20 碼（與超級獎號）。  
- `run_bot.py`：指令列介面。

## 網頁 App（手機可用）

本專案內含**靜態網頁版**，只顯示「最容易出現的 3 個號碼」，可在手機瀏覽器使用。

- **本機預覽**：用瀏覽器開啟 `bingobingo_predictor/web/index.html`。
- **連上 GitHub 後**：推送到 `main` 後，GitHub Actions 會自動部署。網址為：
  - **https://你的帳號.github.io/anya_trade_app/bingobingo/**

請先到 Repo → **Settings** → **Pages** → Source 選擇 **GitHub Actions**（若尚未設定）。部署完成後用手機開啟上述網址即可使用。

網頁會依內建或自訂的近期開獎資料，用頻率＋簡易馬可夫推算並顯示 3 個號碼；可展開「使用自訂開獎資料」貼上自有歷史開獎後重新計算。

## 免責聲明

本專案僅供學習與研究使用。開獎結果具隨機性，模型預測**僅供參考**，請勿作為投注唯一依據，投注前請理性評估風險。
