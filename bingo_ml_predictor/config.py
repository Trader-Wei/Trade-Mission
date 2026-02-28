# -*- coding: utf-8 -*-
"""
Bingo Bingo 預測 Bot 參數與權重設定。
修改此檔即可調整模型參數與整合權重。
"""
from pathlib import Path

# ---------- 路徑 ----------
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
HISTORY_CSV = DATA_DIR / "bingobingo_history.csv"
MODEL_DIR = BASE_DIR / "models"

# ---------- 資料來源 URL（用於分析與取得最新期） ----------
URL_RK = "https://lotto.auzo.tw/RK.php"
URL_ANALYSIS = "https://lotto.auzonet.com/bingobingo_analysis.php"
URL_HISTORY = "https://twlottery.in/lotteryBingo"  # 真實歷史開獎（主頁，約 200+ 期）
URL_HISTORY_LIST = "https://twlottery.in/lotteryBingo/list?date="  # 依日期查詢（可補齊樣本）
URL_AUZO_LIST = "https://lotto.auzo.tw/bingobingo/list_{date}.html"  # 奧索當日列表，date=YYYYMMDD

# ---------- 遊戲常數 ----------
NUM_RANGE = 80       # 01~80
DRAW_SIZE = 20       # 每期開 20 個號碼

# ---------- 特徵與訓練 ----------
LOOKBACK = 80        # 特徵回看期數（隨機搜尋最佳）
MIN_TRAIN_ROWS = 100 # 至少幾期才訓練
TRAIN_TEST_RATIO = 0.85  # 訓練集比例（其餘做回測）
MIN_BACKTEST_PERIODS = 1000  # 回測期數至少 1000 期（歷史總期數需 >= lookback + min_train + 此值）

# ---------- 回測訓練目標（達成率） ----------
TARGET_RATE_MIN = 0.07   # 目標至少 7%
TARGET_RATE_BEST = 0.12  # 理想可達 12%（以 3星中2率 為主指標，輔以 4星中3率）

# ---------- 隨機森林參數 ----------
RF_PARAMS = {
    "n_estimators": 200,
    "max_depth": 12,
    "min_samples_leaf": 4,
    "min_samples_split": 8,
    "random_state": 42,
    "n_jobs": -1,
}

# ---------- XGBoost 參數 ----------
XGB_PARAMS = {
    "n_estimators": 200,
    "max_depth": 8,
    "learning_rate": 0.06,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
    "random_state": 42,
    "n_jobs": -1,
    "eval_metric": "logloss",
}

# ---------- 馬可夫鏈（無額外參數，依歷史轉移矩陣） ----------

# ---------- 整合權重（三者機率加權後取前 20 號，隨機搜尋最佳） ----------
WEIGHT_RANDOM_FOREST = 0.3459
WEIGHT_XGBOOST = 0.3969
WEIGHT_MARKOV = 0.2571

# 權重總和應為 1.0（程式會自動歸一化）
def get_weights():
    w_rf = WEIGHT_RANDOM_FOREST
    w_xgb = WEIGHT_XGBOOST
    w_markov = WEIGHT_MARKOV
    total = w_rf + w_xgb + w_markov
    return w_rf / total, w_xgb / total, w_markov / total
