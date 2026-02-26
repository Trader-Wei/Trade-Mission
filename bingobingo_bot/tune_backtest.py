# -*- coding: utf-8 -*-
"""
學習機制：回測迴圈中搜尋最佳參數，目標「中 3 個」比例 >= 7%。
輸出最佳參數供網頁或後續回測使用。
"""

import sys
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from bingobingo_bot.data_loader import load_history_csv, generate_sample_history, draws_to_matrix
from bingobingo_bot.backtest import run_backtest, draws_array_from_df

TARGET_HIT3_RATE = 0.07  # 目標：中 3 個的比例 >= 7%
NUM_TESTS = 300
MIN_HISTORY = 30


def one_backtest(draws, params, num_tests):
    results, err = run_backtest(draws, num_tests=num_tests, original=False, params=params)
    if err or not results:
        return None, None, None
    n = len(results)
    hit1 = sum(1 for r in results if r >= 1)
    hit2 = sum(1 for r in results if r >= 2)
    hit3 = sum(1 for r in results if r >= 3)
    hit3_rate = hit3 / n
    avg = sum(results) / n
    return hit3_rate, hit1 / n, {"hit1": hit1, "hit2": hit2, "hit3": hit3, "n": n, "avg": avg}


def main():
    import argparse
    parser = argparse.ArgumentParser(description="參數學習：回測迴圈目標中3個>=7%")
    parser.add_argument("--csv", type=str, default=None)
    parser.add_argument("--n", type=int, default=NUM_TESTS, help="回測期數")
    parser.add_argument("--target", type=float, default=TARGET_HIT3_RATE, help="目標中3個比例（預設0.07）")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", type=str, default=None, help="輸出最佳參數 JSON 路徑")
    args = parser.parse_args()

    if args.csv and Path(args.csv).exists():
        df = load_history_csv(args.csv)
        draws = draws_array_from_df(df)
        print(f"從 CSV 載入 {len(draws)} 期")
    else:
        num_draws = max(200, args.n + MIN_HISTORY + 20)
        df = generate_sample_history(num_draws=num_draws, seed=args.seed)
        draws = draws_array_from_df(df)
        print(f"使用模擬 {num_draws} 期（seed={args.seed}）")

    grid = [
        {"weight_decay": w, "markov_bonus": m, "cold_bonus": c, "cold_gap": g}
        for w in [0.95, 0.97, 0.99]
        for m in [0.3, 0.5, 0.7]
        for c in [0.0, 0.15, 0.25, 0.35]
        for g in [5, 10, 15]
    ]

    best_params = None
    best_hit3_rate = -1.0
    best_detail = None
    reached_target = False

    print(f"回測期數={args.n}, 目標中3個>={args.target*100:.0f}%, 參數組合數={len(grid)}")
    print("學習迴圈中...")

    for i, params in enumerate(grid):
        hit3_rate, hit1_rate, detail = one_backtest(draws, params, args.n)
        if hit3_rate is None:
            continue
        if hit3_rate > best_hit3_rate:
            best_hit3_rate = hit3_rate
            best_params = params.copy()
            best_detail = detail
        if hit3_rate >= args.target:
            reached_target = True
            print(f"  [達標] hit3_rate={hit3_rate*100:.1f}% params={params}")
            break
        if (i + 1) % 50 == 0:
            print(f"  已試 {i+1}/{len(grid)}, 目前最佳中3個={best_hit3_rate*100:.1f}%")

    print()
    print("========== 學習結果 ==========")
    if best_params is None:
        print("無有效回測結果")
        return 1
    print(f"最佳參數: {best_params}")
    print(f"中 3 個比例: {best_hit3_rate*100:.1f}%")
    if best_detail:
        print(f"至少中 1 個: {best_detail['hit1']}/{best_detail['n']} ({100*best_detail['hit1']/best_detail['n']:.1f}%)")
        print(f"至少中 2 個: {best_detail['hit2']}/{best_detail['n']} ({100*best_detail['hit2']/best_detail['n']:.1f}%)")
        print(f"平均命中: {best_detail['avg']:.2f} / 3")
    if reached_target:
        print(f"已達目標 >= {args.target*100:.0f}%")
    else:
        print(f"未達目標 {args.target*100:.0f}%，以上為目前最佳參數")

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "params": best_params,
            "hit3_rate": best_hit3_rate,
            "target": args.target,
            "reached_target": reached_target,
            "detail": best_detail,
        }
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        print(f"已寫入 {out_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
