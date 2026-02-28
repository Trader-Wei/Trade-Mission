# Bingo Bingo 預測 Bot（隨機森林 + XGBoost + 馬可夫鏈）

從頭撰寫，使用**真實歷史數據**訓練與回測，並結合兩大分析網頁取得當期資訊。

## 資料來源

- **歷史開獎**：從 [twlottery.in](https://twlottery.in/lotteryBingo) 抓取真實開獎，存成 `data/bingobingo_history.csv`
- **分析頁**：[奧索樂透網 Bingo Bingo 綜合分析](https://lotto.auzonet.com/bingobingo_analysis.php) — 解析當期 20 碼與統計
- **RK 頁**：[lotto.auzo.tw/RK.php](https://lotto.auzo.tw/RK.php) — 備援當期資料（若可連線）

## 模型與權重

| 模型 | 說明 | 預設權重 |
|------|------|----------|
| Random Forest | 80 個二分類器（每號碼是否開出），特徵：出現頻率、上期有無、間隔、冷熱 | 0.35 |
| XGBoost | 同上結構，不同演算法 | 0.40 |
| 馬可夫鏈 | 上期開出→本期開出 / 上期未開→本期開出 的轉移機率 | 0.25 |

整合方式：三者對 1~80 的「開出機率」加權平均後，取分數最高的 20 個號碼作為下期預測。

## 修改參數與權重

- **權重**：編輯 `config.py` 的 `WEIGHT_RANDOM_FOREST`、`WEIGHT_XGBOOST`、`WEIGHT_MARKOV`（程式會自動歸一化）
- **特徵回看期數**：`config.py` 的 `LOOKBACK`（預設 120）
- **隨機森林**：`config.py` 的 `RF_PARAMS`（n_estimators、max_depth、min_samples_leaf 等）
- **XGBoost**：`config.py` 的 `XGB_PARAMS`（n_estimators、max_depth、learning_rate 等）

## 使用流程

### 1. 安裝依賴

```bash
cd bingo_ml_predictor
pip install -r requirements.txt
```

### 2. 取得／補齊歷史數據

**方式一：補齊樣本（建議，目標 1220+ 期供 1000 期回測）**

```bash
python fetch_history_full.py --min-periods 1220 --days-back 400
```

會從 twlottery.in 主頁 + 依日期 list 頁抓取，合併去重後寫入 `data/bingobingo_history.csv`。若該站單頁僅約 200 期，可能需多日執行或手動提供更多歷史 CSV。

**方式二：僅抓主頁（若無 CSV 時自動用）**

```bash
python -c "from data_sources import ensure_history_csv; ensure_history_csv()"
```

或複製既有 CSV：`copy ..\bingobingo_history.csv data\`

### 3. 訓練模型（載入真實數據做學習）

```bash
python train.py
```

可選：`--csv data/bingobingo_history.csv`、`--lookback 120`、`--out-dir models`

### 4. 回測（走前向、真實數據，至少 1000 期）

回測期數至少 **1000 期**（由 `config.py` 的 `MIN_BACKTEST_PERIODS` 設定）。歷史 CSV 總期數需 **≥ lookback + min_train + 1000**（約 1220 期以上），不足時會提示需提供更多歷史資料。

```bash
python backtest.py
```

可選：`--csv`、`--lookback`、`--test-ratio`、`--step`（預設 1，即每期都預測）、`--wr` `--wx` `--wm` 權重

### 5. 權重調校（多組權重回測取較佳）

```bash
python tune_params.py --lookback 120 --step 3
```

依輸出建議修改 `config.py` 的權重。

### 6. 預測下期

```bash
python run_predict.py
```

會自動讀取 bingobingo_analysis.php（與 RK.php）作為參考，並輸出預測 20 碼。

## 目錄結構

```
bingo_ml_predictor/
├── config.py          # 參數與權重（改這裡即可調參）
├── data_sources.py    # 兩網頁 + 歷史 CSV 抓取與解析
├── features.py        # 特徵工程
├── model_rf.py        # 隨機森林
├── model_xgb.py       # XGBoost
├── model_markov.py    # 馬可夫鏈
├── ensemble.py        # 加權整合與取前 20 碼
├── backtest.py        # 回測
├── train.py           # 訓練並儲存模型
├── tune_params.py     # 權重/參數調校
├── run_predict.py     # 主程式：預測下期
├── data/              # 歷史 CSV 存放處
└── models/            # 訓練後的 RF / XGB / 馬可夫模型
```

## 注意事項

- 樂透本質為隨機，本 Bot 僅供研究與娛樂，不保證獲利。
- RK.php 若連線逾時，不影響訓練與預測，僅少一處當期參考。
- 回測為「走前向」：每期只用該期之前資料訓練，再預測該期，評估平均命中數。
