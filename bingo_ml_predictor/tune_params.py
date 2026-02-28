# -*- coding: utf-8 -*-
"""
參數與權重調校：在歷史數據上做回測，嘗試多組權重或 lookback，輸出較佳設定。
可依此修改 config.py 中的 WEIGHT_* 與 LOOKBACK、RF_PARAMS、XGB_PARAMS。
"""
import argparse
from pathlib import Path

from config import HISTORY_CSV, LOOKBACK
from backtest import run_backtest


def _score_backtest(res: dict) -> float:
    """依 3 星中2、3 星全中、4 星中3、4 星全中 給綜合分（愈高愈好）。"""
    return (
        res.get("star3_hit2", 0) * 1
        + res.get("star3_all", 0) * 2
        + res.get("star4_hit3", 0) * 1
        + res.get("star4_all", 0) * 3
    )


def grid_search_weights(
    csv_path: Path = None,
    lookback: int = LOOKBACK,
    test_ratio: float = 0.15,
    step: int = 3,
) -> list:
    """簡單網格搜尋權重 (wr, wx, wm)，回傳 (綜合分, 權重 dict, res) 列表並排序。"""
    candidates = [
        (0.33, 0.34, 0.33),
        (0.35, 0.40, 0.25),
        (0.40, 0.35, 0.25),
        (0.30, 0.45, 0.25),
        (0.25, 0.50, 0.25),
        (0.35, 0.35, 0.30),
        (0.40, 0.40, 0.20),
        (0.30, 0.40, 0.30),
    ]
    results = []
    for wr, wx, wm in candidates:
        res = run_backtest(
            csv_path=csv_path,
            lookback=lookback,
            test_ratio=test_ratio,
            weight_rf=wr,
            weight_xgb=wx,
            weight_markov=wm,
            step=step,
        )
        if "error" in res:
            continue
        score = _score_backtest(res)
        results.append((score, {"weight_rf": wr, "weight_xgb": wx, "weight_markov": wm}, res))
    results.sort(key=lambda x: -x[0])
    return results


def main():
    parser = argparse.ArgumentParser(description="權重與參數調校（回測多組權重）")
    parser.add_argument("--csv", type=str, default=None)
    parser.add_argument("--lookback", type=int, default=LOOKBACK)
    parser.add_argument("--test-ratio", type=float, default=0.15)
    parser.add_argument("--step", type=int, default=3, help="回測每幾期預測一次")
    args = parser.parse_args()
    csv_path = Path(args.csv) if args.csv else None
    results = grid_search_weights(
        csv_path=csv_path,
        lookback=args.lookback,
        test_ratio=args.test_ratio,
        step=args.step,
    )
    print("權重調校結果（按 3星/4星 綜合分由高到低）：")
    for i, (score, weights, full) in enumerate(results[:10], 1):
        print(f"  {i}. 綜合分={score:.0f} | 3星中2={full.get('star3_hit2',0)} 3星全中={full.get('star3_all',0)} 4星中3={full.get('star4_hit3',0)} 4星全中={full.get('star4_all',0)} | RF={weights['weight_rf']} XGB={weights['weight_xgb']} 馬可夫={weights['weight_markov']}")
    if results:
        print("\n建議：將 config.py 中 WEIGHT_RANDOM_FOREST / WEIGHT_XGBOOST / WEIGHT_MARKOV 設為最佳一組權重。")


if __name__ == "__main__":
    main()
