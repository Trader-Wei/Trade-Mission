# -*- coding: utf-8 -*-
"""
回測：用與網頁相同的邏輯（頻率 + 最新一期馬可夫加分）預測 top 3，
統計過往 N 筆的「命中率」。
資料順序：draws[0]=最舊，draws[-1]=最新（回測時用過去預測下一期）。
"""

import numpy as np
import sys
from pathlib import Path

# 專案根目錄
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from bingobingo_bot.data_loader import (
    load_history_csv,
    generate_sample_history,
    draws_to_matrix,
)
from bingobingo_bot.data_loader import NUM_RANGE, DRAW_SIZE

NUM_PER_DRAW = DRAW_SIZE
TOP_N = 3
MIN_HISTORY = 30
WEIGHT_DECAY = 0.95
MARKOV_BONUS = 0.3
COLD_BONUS = 0.0
COLD_GAP = 5


def draws_array_from_df(df):
    """DataFrame (n1..n20) -> list of lists, row i = 20 numbers."""
    mat = draws_to_matrix(df)
    return [list(np.where(mat[i])[0] + 1) for i in range(mat.shape[0])]


def score_and_top3(history_draws, original=False, params=None):
    """
    original=True：原本策略。original=False：使用 params 或預設加強版。
    params: dict 可含 weight_decay, markov_bonus, cold_bonus, cold_gap
    """
    if len(history_draws) < MIN_HISTORY:
        return None
    p = params or {}
    w_decay = p.get("weight_decay", WEIGHT_DECAY)
    m_bonus = p.get("markov_bonus", MARKOV_BONUS)
    c_bonus = p.get("cold_bonus", COLD_BONUS)
    c_gap = p.get("cold_gap", COLD_GAP)
    freq = np.zeros(NUM_RANGE + 1)
    newest = set(history_draws[0])
    for d, draw in enumerate(history_draws):
        w = 1.0 if original else (w_decay ** d)
        for n in draw:
            if 1 <= n <= NUM_RANGE:
                freq[n] += w
    scores = []
    for num in range(1, NUM_RANGE + 1):
        s = float(freq[num])
        if num in newest:
            s += m_bonus
        if not original and c_bonus > 0:
            gap = 0
            for draw in history_draws:
                if num in draw:
                    break
                gap += 1
            if gap > c_gap:
                s += c_bonus
        scores.append((num, s))
    scores.sort(key=lambda x: -x[1])
    return [scores[i][0] for i in range(TOP_N)]


def run_backtest(draws, num_tests=100, original=False, params=None):
    """
    draws: list of 20-number lists, draws[0]=最舊期, draws[-1]=最新期。
    用「過去」預測「下一期」，統計命中次數。
    """
    n = len(draws)
    if n < MIN_HISTORY + 1:
        return None, "期數不足"
    start = max(0, n - num_tests - MIN_HISTORY)
    results = []
    for t in range(start + MIN_HISTORY, n):
        history = [draws[i] for i in range(t - 1, start - 1, -1)]
        pred = score_and_top3(history, original=original, params=params)
        if pred is None:
            continue
        actual = set(draws[t])
        hits = sum(1 for p in pred if p in actual)
        results.append(hits)
    return results, None


def main():
    import argparse
    parser = argparse.ArgumentParser(description="賓果網頁邏輯回測（頻率+馬可夫）")
    parser.add_argument("--csv", type=str, default=None, help="歷史開獎 CSV（無則用模擬）")
    parser.add_argument("--n", type=int, default=100, help="回測期數（預設 100）")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--original", action="store_true", help="用原本策略（單純頻率+馬可夫，無加權與冷號）")
    args = parser.parse_args()

    if args.csv and Path(args.csv).exists():
        df = load_history_csv(args.csv)
        draws = draws_array_from_df(df)
        print(f"從 CSV 載入 {len(draws)} 期")
    else:
        if args.csv:
            print(f"找不到 {args.csv}，改用模擬資料")
        num_draws = max(200, args.n + MIN_HISTORY + 20)
        draws = draws_array_from_df(generate_sample_history(num_draws=num_draws, seed=args.seed))
        print(f"使用模擬 {num_draws} 期（seed={args.seed}）")

    results, err = run_backtest(draws, num_tests=args.n, original=args.original)
    if err:
        print(err)
        return 1

    n = len(results)
    hit1 = sum(1 for r in results if r >= 1)
    hit2 = sum(1 for r in results if r >= 2)
    hit3 = sum(1 for r in results if r >= 3)
    avg_hits = sum(results) / n

    print()
    title = "回測結果（原本策略：頻率+馬可夫）" if args.original else "回測結果（加強版：加權頻率+馬可夫+冷號）"
    print("========== " + title + " ==========")
    print(f"回測期數: {n}")
    print(f"至少中 1 個號碼的期數: {hit1}  ({100*hit1/n:.1f}%)")
    print(f"至少中 2 個號碼的期數: {hit2}  ({100*hit2/n:.1f}%)")
    print(f"中 3 個號碼的期數:     {hit3}  ({100*hit3/n:.1f}%)")
    print(f"平均每期命中個數:      {avg_hits:.2f} / 3")
    print()
    print("（此為歷史回測，實際開獎具隨機性，僅供參考。）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
