# -*- coding: utf-8 -*-
"""
回測訓練：以達成率 7% 為目標、理想 12%，搜尋權重與 lookback 並輸出最佳設定。
可先用較少回測期數快速調參（--min-backtest-periods），資料足夠時再跑滿 1000 期驗證。
"""
import argparse
from pathlib import Path

from config import (
    LOOKBACK,
    HISTORY_CSV,
    MIN_TRAIN_ROWS,
    MIN_BACKTEST_PERIODS,
    TARGET_RATE_MIN,
    TARGET_RATE_BEST,
)
from data_sources import load_history_dataframe
from features import draws_to_matrix
from backtest import run_backtest


def main_rate(res: dict) -> float:
    """主達成率：3星中2率*0.5 + 4星中3率*0.5（兩者較常發生，目標 7%~12%）。"""
    r3 = res.get("star3_hit2_rate", 0.0)
    r4 = res.get("star4_hit3_rate", 0.0)
    return 0.5 * r3 + 0.5 * r4


def run_tune_for_target(
    csv_path: Path = None,
    target_min: float = None,
    target_best: float = None,
    min_backtest_periods: int = None,
    step: int = 1,
) -> dict:
    """
    搜尋權重與 lookback，找出達成率 >= target_min（理想 >= target_best）的設定。
    若歷史期數不足 1000 期，會自動用較少回測期數（min_backtest_periods）先跑。
    """
    target_min = target_min or TARGET_RATE_MIN
    target_best = target_best or TARGET_RATE_BEST
    csv_path = csv_path or HISTORY_CSV
    df = load_history_dataframe(csv_path)
    mat = draws_to_matrix(df)
    T = mat.shape[0]

    # 決定實際回測期數：資料不足時用較少期數
    n_backtest = min_backtest_periods
    min_total_full = LOOKBACK + MIN_TRAIN_ROWS + MIN_BACKTEST_PERIODS
    if n_backtest is None:
        if T >= min_total_full:
            n_backtest = MIN_BACKTEST_PERIODS
        else:
            n_backtest = max(30, (T - LOOKBACK - MIN_TRAIN_ROWS - 10) // 1)
            if n_backtest < 20:
                return {
                    "error": f"歷史期數不足（{T} 期），無法跑回測。至少需約 {LOOKBACK + MIN_TRAIN_ROWS + 30} 期。",
                    "total_periods": T,
                }

    # lookback 候選：資料足用 80/100/120，不足則用 60/80 等以湊出足夠訓練+回測
    if T >= LOOKBACK + MIN_TRAIN_ROWS + n_backtest:
        lookbacks = [80, 100, 120]
    else:
        lookbacks = [lb for lb in [60, 80, 100] if T >= lb + 40 + n_backtest]
        if not lookbacks:
            lookbacks = [max(40, T - n_backtest - MIN_TRAIN_ROWS - 5)]
    weight_candidates = [
        (0.30, 0.45, 0.25),
        (0.35, 0.40, 0.25),
        (0.40, 0.35, 0.25),
        (0.25, 0.50, 0.25),
        (0.33, 0.34, 0.33),
        (0.35, 0.35, 0.30),
        (0.40, 0.40, 0.20),
        (0.28, 0.47, 0.25),
        (0.38, 0.37, 0.25),
        (0.32, 0.43, 0.25),
    ]
    best_rate = -1.0
    best_config = None
    best_res = None
    reached_min = []
    reached_best = []

    for lb in lookbacks:
        min_train = min(MIN_TRAIN_ROWS, T - lb - n_backtest - 5)
        if min_train < 25 or lb + min_train + n_backtest > T:
            continue
        for wr, wx, wm in weight_candidates:
            res = run_backtest(
                csv_path=csv_path,
                lookback=lb,
                min_train=min_train,
                weight_rf=wr,
                weight_xgb=wx,
                weight_markov=wm,
                step=step,
                min_backtest_periods=n_backtest,
            )
            if "error" in res:
                continue
            rate = main_rate(res)
            if rate >= target_min:
                reached_min.append((rate, {"lookback": lb, "weight_rf": wr, "weight_xgb": wx, "weight_markov": wm}, res))
            if rate >= target_best:
                reached_best.append((rate, {"lookback": lb, "weight_rf": wr, "weight_xgb": wx, "weight_markov": wm}, res))
            if rate > best_rate:
                best_rate = rate
                best_config = {"lookback": lb, "weight_rf": wr, "weight_xgb": wx, "weight_markov": wm}
                best_res = res

    return {
        "total_periods": T,
        "backtest_periods_used": n_backtest,
        "target_min": target_min,
        "target_best": target_best,
        "best_rate": best_rate,
        "best_config": best_config,
        "best_res": best_res,
        "reached_min": reached_min,
        "reached_best": reached_best,
    }


def main():
    parser = argparse.ArgumentParser(
        description="回測訓練：目標達成率 7%% 以上、理想 12%%，搜尋最佳權重與 lookback"
    )
    parser.add_argument("--csv", type=str, default=None)
    parser.add_argument("--target-min", type=float, default=TARGET_RATE_MIN, help="目標達成率（預設 0.07）")
    parser.add_argument("--target-best", type=float, default=TARGET_RATE_BEST, help="理想達成率（預設 0.12）")
    parser.add_argument("--min-backtest-periods", type=int, default=None, help="回測期數（未指定則自動：資料足用 1000，不足則盡量多）")
    parser.add_argument("--step", type=int, default=1)
    args = parser.parse_args()
    csv_path = Path(args.csv) if args.csv else None

    out = run_tune_for_target(
        csv_path=csv_path,
        target_min=args.target_min,
        target_best=args.target_best,
        min_backtest_periods=args.min_backtest_periods,
        step=args.step,
    )

    if out.get("error"):
        print(out["error"])
        return

    print(f"歷史總期數: {out['total_periods']}，本次回測期數: {out['backtest_periods_used']}")
    print(f"目標達成率 >= {out['target_min']:.0%}，理想 >= {out['target_best']:.0%}")
    print()

    if out["best_config"]:
        c = out["best_config"]
        r = out["best_res"]
        main_r = main_rate(r)
        print("【最佳設定】達成率:", f"{main_r:.2%}")
        print(f"  lookback={c['lookback']}, RF={c['weight_rf']}, XGB={c['weight_xgb']}, 馬可夫={c['weight_markov']}")
        print(f"  3星中2: {r.get('star3_hit2',0)} 次 ({r.get('star3_hit2_rate',0):.1%}) | 3星全中: {r.get('star3_all',0)} 次 ({r.get('star3_all_rate',0):.1%})")
        print(f"  4星中3: {r.get('star4_hit3',0)} 次 ({r.get('star4_hit3_rate',0):.1%}) | 4星全中: {r.get('star4_all',0)} 次 ({r.get('star4_all_rate',0):.1%})")
        print()
        if main_r >= out["target_min"]:
            print("已達目標 7% 以上。")
        if main_r >= out["target_best"]:
            print("已達理想 12% 以上。")
        print()
        print("請將 config.py 修改為：")
        print(f"  LOOKBACK = {c['lookback']}")
        print(f"  WEIGHT_RANDOM_FOREST = {c['weight_rf']}")
        print(f"  WEIGHT_XGBOOST = {c['weight_xgb']}")
        print(f"  WEIGHT_MARKOV = {c['weight_markov']}")

    n_min = len(out.get("reached_min", []))
    n_best = len(out.get("reached_best", []))
    if n_min > 0:
        print(f"\n共有 {n_min} 組設定達成 >= {out['target_min']:.0%}；其中 {n_best} 組達成 >= {out['target_best']:.0%}。")


if __name__ == "__main__":
    main()
