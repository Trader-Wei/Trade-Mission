# -*- coding: utf-8 -*-
"""
隨機森林：對每個號碼預測「本期是否開出」的機率（80 個二分類器）。
"""
import numpy as np
from sklearn.ensemble import RandomForestClassifier

from config import NUM_RANGE, RF_PARAMS
from features import build_features_labels


class RFBingoModel:
    """80 個 RandomForest 二分類器，每號碼一個。"""

    def __init__(self, **kwargs):
        params = {**RF_PARAMS, **kwargs}
        self.clfs = [RandomForestClassifier(**params) for _ in range(NUM_RANGE)]
        self.lookback = params.get("lookback", 120)

    def fit(self, mat: np.ndarray, lookback: int = None) -> "RFBingoModel":
        lookback = lookback or self.lookback
        X, y = build_features_labels(mat, lookback=lookback)
        if X.shape[0] == 0:
            return self
        T = mat.shape[0]
        n_per_period = NUM_RANGE
        n_periods = (T - lookback)
        for n in range(NUM_RANGE):
            idx = np.arange(n, n_periods * n_per_period, n_per_period)
            X_n, y_n = X[idx], y[idx]
            if np.unique(y_n).size < 2:
                continue
            self.clfs[n].fit(X_n, y_n)
        return self

    def predict_proba(self, mat: np.ndarray, last_t: int, lookback: int = None) -> np.ndarray:
        """依 last_t 期前 lookback 期建特徵，預測 last_t 期對應的 80 維機率。"""
        lookback = lookback or self.lookback
        t = last_t
        if t < lookback:
            return np.full(NUM_RANGE, 0.25, dtype=np.float32)
        window = mat[t - lookback : t]
        curr_row = mat[t]
        proba = np.zeros(NUM_RANGE, dtype=np.float32)
        for n in range(NUM_RANGE):
            hist = window[:, n]
            prev = mat[t - 1, n]
            count_total = hist.sum()
            count_5 = window[-5:].sum(axis=0)[n] if window.shape[0] >= 5 else 0
            count_10 = window[-10:].sum(axis=0)[n] if window.shape[0] >= 10 else 0
            last_idx = np.where(hist[::-1] == 1)[0]
            gap = last_idx[0] + 1 if len(last_idx) > 0 else lookback + 1
            hot = count_5 / 5.0 - count_total / lookback if lookback > 0 else 0.0
            feat = np.array([[
                count_total / lookback,
                float(prev),
                min(gap / (lookback + 1), 1.0),
                count_5 / 5.0,
                count_10 / 10.0,
                hot,
            ]], dtype=np.float32)
            try:
                p = self.clfs[n].predict_proba(feat)[0]
                proba[n] = p[1] if len(p) > 1 else 0.25
            except Exception:
                proba[n] = 0.25
        return proba
