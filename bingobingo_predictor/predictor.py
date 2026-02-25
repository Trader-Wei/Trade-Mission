# -*- coding: utf-8 -*-
"""整合 Random Forest、XGBoost、馬可夫鏈，預測賓果賓果當期號碼。"""

import numpy as np
from pathlib import Path

from .data_loader import (
    load_history_csv,
    draws_to_matrix,
    build_features_from_matrix,
    get_flat_features_and_target,
    generate_sample_history,
    NUM_RANGE,
    DRAW_SIZE,
)
from .markov_model import MarkovBingo
from .models import RFXGBEnsemble


class BingobingoPredictor:
    """
    運用隨機森林 + XGBoost + 馬可夫鏈預測當期 20 個號碼。
    整合方式：對每個號碼 1~80 計算加權平均「出現機率」，取機率最高的 20 個。
    """

    def __init__(
        self,
        lookback: int = 100,
        weight_rf: float = 0.35,
        weight_xgb: float = 0.35,
        weight_markov: float = 0.30,
    ):
        self.lookback = lookback
        self.weight_rf = weight_rf
        self.weight_xgb = weight_xgb
        self.weight_markov = weight_markov
        self.ensemble = RFXGBEnsemble()
        self.markov = MarkovBingo()
        self.mat = None  # (T, 80) 歷史 0/1
        self.fitted = False

    def fit(self, draws_df):
        """
        draws_df: DataFrame，含 n1..n20 或等效欄位（每期 20 個號碼）。
        """
        self.mat = draws_to_matrix(draws_df)
        T = self.mat.shape[0]
        if T < self.lookback + 5:
            raise ValueError(f"歷史期數至少需 {self.lookback + 5} 期，目前 {T} 期")

        # 特徵與目標（從 lookback 開始才有特徵）
        X_flat, y_flat, _ = get_flat_features_and_target(self.mat, self.lookback)
        self.ensemble.fit(X_flat, y_flat)
        self.markov.fit(self.mat)
        self.fitted = True
        return self

    def _last_draw_features(self) -> np.ndarray:
        """依最近 lookback 期與上一期，產生「下一期」每個號碼的特徵 (80, n_features)。"""
        X, _, _ = build_features_from_matrix(self.mat, self.lookback)
        # 最後一筆特徵就是「下一期」的輸入
        return X[-1]  # (80, n_features)

    def predict_proba_per_number(self) -> np.ndarray:
        """
        回傳 (80,) 各號碼「在當期開出」的整合機率。
        """
        if not self.fitted:
            raise RuntimeError("請先呼叫 fit() 以歷史資料訓練模型")

        last_draw = self.mat[-1]  # (80,)
        feat = self._last_draw_features()  # (80, n_features)，每號碼一列

        p_rf = self.ensemble.predict_proba_rf(feat)
        p_xgb = self.ensemble.predict_proba_xgb(feat)
        p_markov = self.markov.predict_proba(last_draw)

        # 歸一化到相近尺度（可選）：馬可夫已是機率；RF/XGB 也是 [0,1]
        p_ensemble = (
            self.weight_rf * p_rf
            + self.weight_xgb * p_xgb
            + self.weight_markov * p_markov
        )
        return p_ensemble

    def predict_current_draw(self, top_k: int = DRAW_SIZE) -> np.ndarray:
        """
        預測「當期」開出的 top_k 個號碼（預設 20）。
        回傳由小到大排序的號碼陣列，值域 1~80。
        """
        proba = self.predict_proba_per_number()
        # 取機率最高的 top_k 個號碼（1-indexed）
        indices = np.argsort(proba)[::-1][:top_k]
        numbers = (indices + 1).astype(int)  # 0-index -> 1~80
        return np.sort(numbers)

    def predict_top3(self) -> np.ndarray:
        """預測最容易出現的 3 個號碼（1~80，由小到大）。"""
        return self.predict_current_draw(top_k=3)

    def predict_with_super(self) -> tuple:
        """
        預測當期 20 個號碼 + 1 個超級獎號。
        超級獎號：取機率第 21 高的號碼（或可改為另建模型）。
        """
        proba = self.predict_proba_per_number()
        indices = np.argsort(proba)[::-1][:21]
        numbers = (indices + 1).astype(int)
        main_20 = np.sort(numbers[:20])
        super_num = numbers[20]
        return main_20, super_num


def run_from_csv(
    csv_path: str,
    lookback: int = 100,
    weight_rf: float = 0.35,
    weight_xgb: float = 0.35,
    weight_markov: float = 0.30,
) -> BingobingoPredictor:
    """從 CSV 載入歷史、訓練、回傳已擬合的預測器。"""
    draws = load_history_csv(csv_path)
    pred = BingobingoPredictor(lookback=lookback, weight_rf=weight_rf, weight_xgb=weight_xgb, weight_markov=weight_markov)
    pred.fit(draws)
    return pred


def run_with_sample_data(
    num_draws: int = 500,
    lookback: int = 100,
    seed: int = 42,
) -> BingobingoPredictor:
    """使用模擬歷史資料訓練並回傳預測器（示範用）。"""
    draws = generate_sample_history(num_draws=num_draws, seed=seed)
    pred = BingobingoPredictor(lookback=lookback)
    pred.fit(draws)
    return pred
