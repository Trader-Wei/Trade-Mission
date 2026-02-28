# -*- coding: utf-8 -*-
"""
隨機取樣訓練迴圈：以「3 星全中」穩定 7% 以上為目標，
隨機抽樣 lookback 與整合權重，回測後取最佳設定並可寫入 config + 訓練一次。
"""
import argparse
import json
import random
import sys
from pathlib import Path

from config import (
    LOOKBACK,
    MIN_TRAIN_ROWS,
    HISTORY_CSV,
)
from data_sources import load_history_dataframe
from features import draws_to_matrix
from backtest import run_backtest

TARGET_STAR3_ALL = 0.07  # 3 星全中目標 7%


def sample_config(rng: random.Random):
    """隨機一組 lookback 與權重 (wr, wx, wm)，權重歸一化。"""
    lookback = rng.choice([60, 80, 100, 120])
    wr = rng.uniform(0.2, 0.5)
    wx = rng.uniform(0.2, 0.5)
    wm = rng.uniform(0.15, 0.35)
    total = wr + wx + wm
    return lookback, wr / total, wx / total, wm / total


def run_random_loop(
    csv_path: Path = None,
    n_trials: int = 30,
    min_backtest_periods: int = 100,
    step: int = 5,
    seed: int = 42,
    stable_checks: int = 0,
    best_config_path: Path = None,
) -> dict:
    """
    隨機取樣 n_trials 組參數，回測後選出 3 星全中率 >= TARGET_STAR3_ALL 且最高的設定。
    stable_checks: 對最佳設定再用幾組不同 step 各跑一次，取平均當穩定估計（0=不跑）。
    """
    csv_path = csv_path or HISTORY_CSV
    df = load_history_dataframe(csv_path)
    mat = draws_to_matrix(df)
    T = mat.shape[0]

    min_total = 120 + MIN_TRAIN_ROWS + min_backtest_periods  # 保守用 max lookback
    if T < min_total:
        return {
            "error": f"歷史期數不足：目前 {T} 期，至少需約 {min_total} 期。",
            "total_periods": T,
        }

    rng = random.Random(seed)
    best_rate = -1.0
    best_config = None
    best_res = None
    reached = []
    if best_config_path:
        best_config_path.parent.mkdir(parents=True, exist_ok=True)

    for i in range(n_trials):
        lookback, wr, wx, wm = sample_config(rng)
        res = run_backtest(
            csv_path=csv_path,
            lookback=lookback,
            min_backtest_periods=min_backtest_periods,
            step=step,
            weight_rf=wr,
            weight_xgb=wx,
            weight_markov=wm,
        )
        if "error" in res:
            continue
        r3all = res.get("star3_all_rate", 0.0)
        if r3all >= TARGET_STAR3_ALL:
            reached.append((r3all, lookback, wr, wx, wm, res))
        if r3all > best_rate:
            best_rate = r3all
            best_config = {"lookback": lookback, "weight_rf": wr, "weight_xgb": wx, "weight_markov": wm}
            best_res = res
            if best_config_path:
                best_config_path.write_text(
                    json.dumps({"best_config": best_config, "best_rate": best_rate}, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
        msg = f"  trial {i+1}/{n_trials} lookback={lookback} wr={wr:.2f} wx={wx:.2f} wm={wm:.2f} -> 3星全中 {r3all:.1%}\n"
        print(msg, end="")
        sys.stdout.flush()

    # 若沒有任何一組達標，仍回傳最佳一組（可能 < 7%）
    stable_rate = None
    if best_config and stable_checks > 0:
        steps_to_try = [step + (i % 3) * 2 for i in range(stable_checks)]  # 例如 5,7,9
        rates = []
        for s in steps_to_try:
            if s < 1:
                s = 1
            r = run_backtest(
                csv_path=csv_path,
                lookback=best_config["lookback"],
                min_backtest_periods=min_backtest_periods,
                step=s,
                weight_rf=best_config["weight_rf"],
                weight_xgb=best_config["weight_xgb"],
                weight_markov=best_config["weight_markov"],
            )
            if "error" not in r:
                rates.append(r.get("star3_all_rate", 0.0))
        stable_rate = sum(rates) / len(rates) if rates else best_rate

    return {
        "total_periods": T,
        "target_star3_all": TARGET_STAR3_ALL,
        "n_trials": n_trials,
        "best_rate": best_rate,
        "best_config": best_config,
        "best_res": best_res,
        "reached_target": reached,
        "stable_rate": stable_rate,
    }


def apply_config(config_path: Path, cfg: dict) -> None:
    """將最佳 lookback 與權重寫入 config.py。"""
    path = config_path or (Path(__file__).resolve().parent / "config.py")
    text = path.read_text(encoding="utf-8")
    c = cfg["best_config"]
    # 替換 LOOKBACK = 數字
    import re
    text = re.sub(r"^LOOKBACK\s*=\s*\d+", f"LOOKBACK = {c['lookback']}", text, flags=re.MULTILINE)
    text = re.sub(
        r"^WEIGHT_RANDOM_FOREST\s*=\s*[\d.]+",
        f"WEIGHT_RANDOM_FOREST = {c['weight_rf']:.4f}",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^WEIGHT_XGBOOST\s*=\s*[\d.]+",
        f"WEIGHT_XGBOOST = {c['weight_xgb']:.4f}",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^WEIGHT_MARKOV\s*=\s*[\d.]+",
        f"WEIGHT_MARKOV = {c['weight_markov']:.4f}",
        text,
        flags=re.MULTILINE,
    )
    path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(
        description="隨機取樣訓練迴圈，目標 3 星全中穩定 7%% 以上"
    )
    parser.add_argument("--csv", type=str, default=None)
    parser.add_argument("--trials", type=int, default=30, help="隨機取樣組數")
    parser.add_argument("--min-backtest-periods", type=int, default=100)
    parser.add_argument("--step", type=int, default=5)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--stable-checks", type=int, default=0, help="對最佳設定再跑幾次不同 step 求穩定率")
    parser.add_argument("--apply", action="store_true", help="將最佳參數寫入 config.py 並執行 train.py")
    parser.add_argument("--best-out", type=str, default=None, help="每輪最佳參數寫入的 JSON 檔路徑")
    parser.add_argument("--apply-from", type=str, default=None, help="從指定 JSON 套用最佳參數並訓練（不跑迴圈）")
    args = parser.parse_args()
    csv_path = Path(args.csv) if args.csv else None
    best_config_path = Path(args.best_out) if args.best_out else (Path(__file__).resolve().parent / "data" / "best_config.json")

    if args.apply_from:
        jpath = Path(args.apply_from)
        if not jpath.exists():
            print(f"找不到檔案: {jpath}")
            return
        data = json.loads(jpath.read_text(encoding="utf-8"))
        cfg = data.get("best_config")
        if not cfg:
            print("JSON 內無 best_config")
            return
        out = {"best_config": cfg, "best_res": None}
        apply_config(None, out)
        print("已寫入 config.py，正在執行 train.py ...")
        from train import train_all
        train_all(csv_path=csv_path or HISTORY_CSV)
        print("訓練完成。")
        return

    print(f"目標: 3 星全中 >= {TARGET_STAR3_ALL:.0%}")
    print(f"隨機取樣 {args.trials} 組，回測期數 {args.min_backtest_periods}，step={args.step}")
    print()

    out = run_random_loop(
        csv_path=csv_path,
        n_trials=args.trials,
        min_backtest_periods=args.min_backtest_periods,
        step=args.step,
        seed=args.seed,
        stable_checks=args.stable_checks,
        best_config_path=best_config_path,
    )

    if out.get("error"):
        print(out["error"])
        return

    c = out["best_config"]
    r = out["best_res"]
    print()
    print("【最佳設定】")
    print(f"  lookback={c['lookback']}, RF={c['weight_rf']:.4f}, XGB={c['weight_xgb']:.4f}, 馬可夫={c['weight_markov']:.4f}")
    print(f"  3星全中: {r['star3_all']} 次 ({r['star3_all_rate']:.1%})")
    print(f"  3星中2:  {r['star3_hit2']} 次 ({r['star3_hit2_rate']:.1%})")
    print(f"  4星中3:  {r['star4_hit3']} 次 ({r['star4_hit3_rate']:.1%})")
    print(f"  4星全中: {r['star4_all']} 次 ({r['star4_all_rate']:.1%})")
    if out.get("stable_rate") is not None:
        print(f"  穩定估計（多 step 平均）: {out['stable_rate']:.1%}")
    n_reached = len(out.get("reached_target", []))
    print(f"\n達標 (>= {TARGET_STAR3_ALL:.0%}) 的組數: {n_reached}")

    if args.apply and c:
        apply_config(None, out)
        print("\n已寫入 config.py，正在執行 train.py ...")
        from train import train_all
        train_all(csv_path=csv_path or HISTORY_CSV)
        print("訓練完成。")
    else:
        print("\n若要套用並訓練，請加上 --apply")


if __name__ == "__main__":
    main()
