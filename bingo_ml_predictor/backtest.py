# -*- coding: utf-8 -*-
"""
使用真實歷史數據做走前向回測：每期用過去資料訓練 RF / XGB / 馬可夫，預測下一期。
僅統計：3 星（中 2 碼、全中）、4 星（中 3 碼、全中）。
"""
import numpy as np
from pathlib import Path

from config import (
    LOOKBACK,
    MIN_TRAIN_ROWS,
    TRAIN_TEST_RATIO,
    MIN_BACKTEST_PERIODS,
    get_weights,
)
from data_sources import load_history_dataframe, HISTORY_CSV
from features import draws_to_matrix
from model_rf import RFBingoModel
from model_xgb import XGBBingoModel
from model_markov import MarkovModel
from ensemble import predict_next_20_by_score_order


def run_backtest(
    csv_path: Path = None,
    lookback: int = LOOKBACK,
    min_train: int = MIN_TRAIN_ROWS,
    test_ratio: float = None,
    weight_rf: float = None,
    weight_xgb: float = None,
    weight_markov: float = None,
    step: int = 1,
    min_backtest_periods: int = None,
) -> dict:
    """
    回測流程：每期預測 20 碼（依分數排序），取前 3 碼為 3 星、前 4 碼為 4 星。
    只統計：3 星中 2、3 星全中、4 星中 3、4 星全中。
    min_backtest_periods: 若指定則覆寫 config 的 MIN_BACKTEST_PERIODS（可用於資料不足時先跑少量期數調參）。
    """
    csv_path = csv_path or HISTORY_CSV
    df = load_history_dataframe(csv_path)
    mat = draws_to_matrix(df)
    T = mat.shape[0]
    n_required = min_backtest_periods if min_backtest_periods is not None else MIN_BACKTEST_PERIODS
    min_total = lookback + min_train + n_required
    if T < min_total:
        return {
            "error": f"歷史期數不足：目前 {T} 期，回測至少需 {n_required} 期，總期數需 >= {min_total} 期（lookback + min_train + 回測期數）。請提供更多歷史 CSV 或從 twlottery.in 取得更多資料。",
            "total_periods": T,
            "min_required": min_total,
        }
    test_ratio = test_ratio or (1 - TRAIN_TEST_RATIO)
    n_test = max(n_required, int(T * test_ratio))
    start_test = T - n_test
    if start_test < lookback + min_train:
        start_test = lookback + min_train
        n_test = T - start_test
    if start_test >= T or n_test < 1:
        return {"error": "無可回測期數（歷史期數不足）", "total_periods": T}

    w_rf, w_xgb, w_markov = get_weights()
    if weight_rf is not None:
        w_rf, w_xgb, w_markov = weight_rf, weight_xgb, weight_markov
        total = w_rf + w_xgb + w_markov
        w_rf, w_xgb, w_markov = w_rf / total, w_xgb / total, w_markov / total

    # 只統計這四項
    star3_hit2 = 0   # 3 星中 2 碼
    star3_all = 0    # 3 星全中
    star4_hit3 = 0   # 4 星中 3 碼
    star4_all = 0    # 4 星全中
    n_periods = 0

    for t in range(start_test, T, step):
        train_mat = mat[:t]
        if train_mat.shape[0] < lookback + 20:
            continue
        rf = RFBingoModel()
        rf.fit(train_mat, lookback=lookback)
        xgb = XGBBingoModel()
        xgb.fit(train_mat, lookback=lookback)
        markov = MarkovModel()
        markov.fit(train_mat)
        p_rf = rf.predict_proba(mat, t, lookback=lookback)
        p_xgb = xgb.predict_proba(mat, t, lookback=lookback)
        p_markov = markov.predict_proba(mat[t - 1])
        # 依分數由高到低，前 3 碼=3 星、前 4 碼=4 星
        pred_ordered = predict_next_20_by_score_order(p_rf, p_xgb, p_markov, w_rf, w_xgb, w_markov)
        bet_3 = set(pred_ordered[:3])
        bet_4 = set(pred_ordered[:4])
        actual = set(np.where(mat[t] == 1)[0] + 1)
        h3 = len(actual & bet_3)
        h4 = len(actual & bet_4)
        if h3 == 2:
            star3_hit2 += 1
        if h3 == 3:
            star3_all += 1
        if h4 == 3:
            star4_hit3 += 1
        if h4 == 4:
            star4_all += 1
        n_periods += 1

    if n_periods == 0:
        return {"error": "無有效回測步", "total_periods": T}

    return {
        "total_periods": T,
        "backtest_periods": n_periods,
        "star3_hit2": star3_hit2,
        "star3_hit2_rate": star3_hit2 / n_periods,
        "star3_all": star3_all,
        "star3_all_rate": star3_all / n_periods,
        "star4_hit3": star4_hit3,
        "star4_hit3_rate": star4_hit3 / n_periods,
        "star4_all": star4_all,
        "star4_all_rate": star4_all / n_periods,
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Bingo Bingo 回測（RF+XGB+馬可夫）")
    parser.add_argument("--csv", type=str, default=None, help="歷史 CSV 路徑")
    parser.add_argument("--lookback", type=int, default=LOOKBACK, help="特徵回看期數")
    parser.add_argument("--test-ratio", type=float, default=None, help="測試集比例")
    parser.add_argument("--step", type=int, default=1, help="每幾期做一次預測")
    parser.add_argument("--min-backtest-periods", type=int, default=None, help="最少回測期數（未指定則用 config）")
    parser.add_argument("--wr", type=float, default=None, help="RF 權重")
    parser.add_argument("--wx", type=float, default=None, help="XGB 權重")
    parser.add_argument("--wm", type=float, default=None, help="馬可夫權重")
    args = parser.parse_args()
    csv_path = Path(args.csv) if args.csv else None
    res = run_backtest(
        csv_path=csv_path,
        lookback=args.lookback,
        test_ratio=args.test_ratio,
        weight_rf=args.wr,
        weight_xgb=args.wx,
        weight_markov=args.wm,
        step=args.step,
        min_backtest_periods=args.min_backtest_periods,
    )
    if "error" in res:
        print(res["error"], res)
    else:
        print(f"回測期數: {res['backtest_periods']}（總歷史 {res['total_periods']} 期）")
        print("--- 3 星 ---")
        print(f"  中 2 碼: {res['star3_hit2']} 次 ({res['star3_hit2_rate']:.1%})")
        print(f"  全中:   {res['star3_all']} 次 ({res['star3_all_rate']:.1%})")
        print("--- 4 星 ---")
        print(f"  中 3 碼: {res['star4_hit3']} 次 ({res['star4_hit3_rate']:.1%})")
        print(f"  全中:   {res['star4_all']} 次 ({res['star4_all_rate']:.1%})")
    return res


if __name__ == "__main__":
    main()
