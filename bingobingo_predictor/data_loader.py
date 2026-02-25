# -*- coding: utf-8 -*-
"""賓果賓果歷史開獎資料載入與特徵工程。"""

import pandas as pd
import numpy as np
from pathlib import Path

# 賓果賓果：01~80 選 20 個號碼
NUM_RANGE = 80
DRAW_SIZE = 20


def load_history_csv(path: str) -> pd.DataFrame:
    """
    從 CSV 載入歷史開獎。
    預期格式：期別, 號碼1, 號碼2, ..., 號碼20（可選：超級獎號）
    或：期別, 開獎日期, n1, n2, ..., n20
    欄位名可為數字或 n1..n20。
    """
    df = pd.read_csv(path, encoding="utf-8-sig")
    # 找出號碼欄：n1..n20 或 1..20 或 號碼1..號碼20
    num_cols = []
    for c in df.columns:
        cstr = str(c).strip()
        if cstr.isdigit() and 1 <= int(cstr) <= 20:
            num_cols.append((int(cstr), c))
        elif cstr.lower().startswith("n") and cstr[1:].isdigit():
            n = int(cstr[1:])
            if 1 <= n <= 20:
                num_cols.append((n, c))
        elif "號碼" in cstr or "num" in cstr.lower():
            for i in range(1, 21):
                if str(i) in cstr or f"n{i}" in cstr.lower():
                    num_cols.append((i, c))
                    break
    num_cols.sort(key=lambda x: x[0])
    if len(num_cols) < 20:
        # 嘗試依欄位順序取前 20 個數字欄
        num_cols = []
        for i, c in enumerate(df.columns):
            if i == 0 and (df[c].dtype == object or "期" in str(c)):
                continue
            if pd.api.types.is_numeric_dtype(df[c]):
                num_cols.append((len(num_cols) + 1, c))
            if len(num_cols) >= 20:
                break
    if len(num_cols) < 20:
        raise ValueError(f"CSV 需要至少 20 個號碼欄，目前找到: {[x[1] for x in num_cols]}")
    cols = [x[1] for x in num_cols[:20]]
    out = df[cols].copy()
    out.columns = [f"n{i}" for i in range(1, 21)]
    if "期別" in df.columns or "期" in str(df.columns[0]):
        out.insert(0, "period", df.iloc[:, 0])
    else:
        out.insert(0, "period", np.arange(len(df)))
    return out


def draws_to_matrix(draws: pd.DataFrame) -> np.ndarray:
    """每期 20 個號碼 -> 每期 80 維 0/1 向量。"""
    mat = np.zeros((len(draws), NUM_RANGE), dtype=np.int8)
    for i, row in draws.iterrows():
        for j in range(1, 21):
            v = row.get(f"n{j}", row.iloc[j] if j < len(row) else 0)
            n = int(v)
            if 1 <= n <= NUM_RANGE:
                mat[i, n - 1] = 1
    return mat


def build_features_from_matrix(mat: np.ndarray, lookback: int = 100) -> tuple:
    """
    從歷史 0/1 矩陣建特徵。
    mat: (T, 80)，T=期數
    回傳: X (T, 80, n_features), y (T, 80) 當期是否開出
    """
    T = mat.shape[0]
    # 特徵：過去 lookback 期出現次數、距上次出現間隔、上期是否出現（給馬可夫用）
    n_features = 4
    X = np.zeros((T, NUM_RANGE, n_features), dtype=np.float32)
    y = mat.copy()

    for t in range(lookback, T):
        for n in range(NUM_RANGE):
            window = mat[t - lookback : t, n]
            freq = window.sum()
            X[t, n, 0] = freq / lookback  # 近期出現頻率
            # 距上次出現間隔
            last_pos = np.where(window[::-1] == 1)[0]
            gap = lookback if len(last_pos) == 0 else last_pos[0]
            X[t, n, 1] = min(gap / lookback, 1.0)
            # 上期是否出現
            X[t, n, 2] = mat[t - 1, n]
            # 前幾期出現次數的平滑
            X[t, n, 3] = (mat[t - 5 : t, n].sum() / 5.0) if t >= 5 else 0.0

    return X, y, lookback


def get_flat_features_and_target(mat: np.ndarray, lookback: int = 100):
    """
    將 (T, 80, n_features) 攤平為 (T*80, n_features)，目標 (T*80,)。
    用於訓練 RF / XGBoost：每期每個號碼一筆樣本，預測該號碼當期是否開出。
    """
    X, y, lb = build_features_from_matrix(mat, lookback)
    T = X.shape[0]
    X_flat = X.reshape(T * NUM_RANGE, -1)
    y_flat = y.reshape(T * NUM_RANGE,)
    return X_flat, y_flat, lb


def generate_sample_history(num_draws: int = 500, seed: int = 42) -> pd.DataFrame:
    """產生模擬歷史開獎（每期 20 個不重複 1~80），供無真實資料時測試。"""
    rng = np.random.default_rng(seed)
    rows = []
    for i in range(num_draws):
        draw = rng.choice(np.arange(1, NUM_RANGE + 1), size=DRAW_SIZE, replace=False)
        row = {"period": i + 1, **{f"n{j+1}": draw[j] for j in range(20)}}
        rows.append(row)
    return pd.DataFrame(rows)
