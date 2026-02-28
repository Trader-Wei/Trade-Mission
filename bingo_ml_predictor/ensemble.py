# -*- coding: utf-8 -*-
"""
整合 Random Forest、XGBoost、馬可夫鏈的預測機率，依權重加總後取前 20 號為下期預測。
"""
import numpy as np
from config import NUM_RANGE, DRAW_SIZE, get_weights


def combine_and_pick(
    proba_rf: np.ndarray,
    proba_xgb: np.ndarray,
    proba_markov: np.ndarray,
    weight_rf: float = None,
    weight_xgb: float = None,
    weight_markov: float = None,
) -> np.ndarray:
    """
    三者機率加權後，回傳分數（可排序）。再依分數取前 DRAW_SIZE 個號碼（1-indexed）。
    """
    w_rf, w_xgb, w_markov = get_weights()
    if weight_rf is not None:
        w_rf = weight_rf
    if weight_xgb is not None:
        w_xgb = weight_xgb
    if weight_markov is not None:
        w_markov = weight_markov
    total = w_rf + w_xgb + w_markov
    w_rf, w_xgb, w_markov = w_rf / total, w_xgb / total, w_markov / total

    combined = w_rf * np.asarray(proba_rf, dtype=np.float64) + \
               w_xgb * np.asarray(proba_xgb, dtype=np.float64) + \
               w_markov * np.asarray(proba_markov, dtype=np.float64)
    return combined


def predict_next_20(
    proba_rf: np.ndarray,
    proba_xgb: np.ndarray,
    proba_markov: np.ndarray,
    weight_rf: float = None,
    weight_xgb: float = None,
    weight_markov: float = None,
) -> list:
    """回傳預測的下期 20 個號碼（1~80，已排序）。"""
    combined = combine_and_pick(proba_rf, proba_xgb, proba_markov, weight_rf, weight_xgb, weight_markov)
    top_idx = np.argsort(combined)[::-1][:DRAW_SIZE]
    return sorted([int(i) + 1 for i in top_idx])


def predict_next_20_by_score_order(
    proba_rf: np.ndarray,
    proba_xgb: np.ndarray,
    proba_markov: np.ndarray,
    weight_rf: float = None,
    weight_xgb: float = None,
    weight_markov: float = None,
) -> list:
    """回傳預測的 20 碼，依加權分數由高到低（第 1 個最看好）。用於 3 星／4 星：前 3 碼=3 星、前 4 碼=4 星。"""
    combined = combine_and_pick(proba_rf, proba_xgb, proba_markov, weight_rf, weight_xgb, weight_markov)
    top_idx = np.argsort(combined)[::-1][:DRAW_SIZE]
    return [int(i) + 1 for i in top_idx]
