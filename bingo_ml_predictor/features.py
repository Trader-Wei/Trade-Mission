# -*- coding: utf-8 -*-
"""
從歷史開獎建特徵與標籤，供 Random Forest、XGBoost、馬可夫鏈使用。
"""
import numpy as np
import pandas as pd
from typing import Tuple

from config import NUM_RANGE, DRAW_SIZE, LOOKBACK


def draws_to_matrix(draws: pd.DataFrame) -> np.ndarray:
    """每期 20 個號碼 -> (T, 80) 0/1 矩陣。"""
    mat = np.zeros((len(draws), NUM_RANGE), dtype=np.int8)
    for i, row in draws.iterrows():
        for j in range(1, 21):
            v = row.get(f"n{j}", row.iloc[j] if j < len(row) else 0)
            n = int(v)
            if 1 <= n <= NUM_RANGE:
                mat[i, n - 1] = 1
    return mat


def build_features_labels(
    mat: np.ndarray,
    lookback: int = LOOKBACK,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    mat: (T, 80) 每期 0/1
    對每個號碼 n、每期 t >= lookback，建特徵並標籤 y = 當期 n 是否開出。
    回傳 X (N, n_features), y (N)，N = (T - lookback) * 80。
    """
    T = mat.shape[0]
    n_features = 6
    # 特徵：過去 lookback 出現次數、上期是否出現、距上次出現間隔、近期 5/10 期出現次數、冷熱
    X_list = []
    y_list = []
    for t in range(lookback, T):
        window = mat[t - lookback : t]
        curr = mat[t]
        for n in range(NUM_RANGE):
            hist = window[:, n]
            prev = mat[t - 1, n]
            count_total = hist.sum()
            count_5 = window[-5:].sum(axis=0)[n] if window.shape[0] >= 5 else 0
            count_10 = window[-10:].sum(axis=0)[n] if window.shape[0] >= 10 else 0
            # 距上次出現
            last_idx = np.where(hist[::-1] == 1)[0]
            gap = last_idx[0] + 1 if len(last_idx) > 0 else lookback + 1
            # 冷熱：近期 vs 整體
            hot = count_5 / 5.0 - count_total / lookback if lookback > 0 else 0.0
            feat = [
                count_total / lookback,
                float(prev),
                min(gap / (lookback + 1), 1.0),
                count_5 / 5.0,
                count_10 / 10.0,
                hot,
            ]
            X_list.append(feat)
            y_list.append(int(curr[n]))
    if not X_list:
        return np.zeros((0, n_features), dtype=np.float32), np.zeros(0, dtype=np.int32)
    return np.array(X_list, dtype=np.float32), np.array(y_list, dtype=np.int32)


def build_features_per_number(
    mat: np.ndarray,
    lookback: int = LOOKBACK,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    每期 t 建 80 組特徵（每號碼一組），標籤為當期 80 維 0/1。
    回傳 X (T', 80, n_features), y (T', 80)，T' = T - lookback。
    供需要「每期每號碼」預測的流程使用。
    """
    T = mat.shape[0]
    n_features = 6
    X = np.zeros((T - lookback, NUM_RANGE, n_features), dtype=np.float32)
    y = np.zeros((T - lookback, NUM_RANGE), dtype=np.int8)
    for t in range(lookback, T):
        window = mat[t - lookback : t]
        curr = mat[t]
        for n in range(NUM_RANGE):
            hist = window[:, n]
            prev = mat[t - 1, n]
            count_total = hist.sum()
            count_5 = window[-5:].sum(axis=0)[n] if window.shape[0] >= 5 else 0
            count_10 = window[-10:].sum(axis=0)[n] if window.shape[0] >= 10 else 0
            last_idx = np.where(hist[::-1] == 1)[0]
            gap = last_idx[0] + 1 if len(last_idx) > 0 else lookback + 1
            hot = count_5 / 5.0 - count_total / lookback if lookback > 0 else 0.0
            X[t - lookback, n, :] = [
                count_total / lookback,
                float(prev),
                min(gap / (lookback + 1), 1.0),
                count_5 / 5.0,
                count_10 / 10.0,
                hot,
            ]
            y[t - lookback, n] = curr[n]
    return X, y
