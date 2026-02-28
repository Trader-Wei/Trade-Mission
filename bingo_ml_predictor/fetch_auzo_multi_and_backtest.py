# -*- coding: utf-8 -*-
"""
擷取多個日期的奧索 list 頁，與既有 CSV 合併後執行訓練與回測。
用法: python fetch_auzo_multi_and_backtest.py 20260226 20260225 20260224 20260223
"""
import csv
import sys
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import HISTORY_CSV
from data_sources import fetch_auzo_list_page

def load_existing():
    """載入既有 CSV，回傳 { period: [n1..n20] }"""
    if not HISTORY_CSV.exists():
        return {}
    by_period = {}
    with open(HISTORY_CSV, "r", encoding="utf-8-sig") as f:
        r = csv.reader(f)
        next(r, None)
        for row in r:
            if len(row) >= 21:
                by_period[row[0]] = [int(x) for x in row[1:21]]
    return by_period

def main():
    dates = ["20260226", "20260225", "20260224", "20260223"]
    if len(sys.argv) > 1:
        dates = [d.replace("-", "") for d in sys.argv[1:]]
    by_period = load_existing()
    print(f"既有 {len(by_period)} 期，開始抓取 {dates} …")
    for date_str in dates:
        draws, periods = fetch_auzo_list_page(date_str)
        for p, row in zip(periods, draws):
            by_period[p] = row
        print(f"  {date_str}: +{len(draws)} 期，累計 {len(by_period)} 期")
    if not by_period:
        print("無任何資料")
        return
    sorted_periods = sorted(by_period.keys(), key=lambda x: int(x))
    HISTORY_CSV.parent.mkdir(parents=True, exist_ok=True)
    with open(HISTORY_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["period"] + [f"n{i}" for i in range(1, 21)])
        for p in sorted_periods:
            w.writerow([p] + by_period[p])
    print(f"\n已合併寫入 {HISTORY_CSV}，共 {len(sorted_periods)} 期。")
    # 報告
    report_path = Path(__file__).parent / "data" / "auzo_draws_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(f"已寫入 {HISTORY_CSV}，共 {len(sorted_periods)} 期（最舊→最新）。\n\n")
        f.write("=== 期號與開獎號碼（最新在前）===\n\n")
        for p in reversed(sorted_periods):
            row = by_period[p]
            nums_str = ", ".join(f"{n:02d}" for n in row)
            f.write(f"{p} | {nums_str}\n")
        f.write(f"\n共 {len(sorted_periods)} 期。\n")
    print(f"報告: {report_path}\n")
    # 訓練
    print("開始訓練 …")
    subprocess.run([sys.executable, str(Path(__file__).parent / "train.py")], check=True, cwd=str(Path(__file__).parent))
    # 回測（若不足 1220 期則用 --min-backtest-periods 放寬）
    print("\n開始回測 …")
    backtest_script = Path(__file__).parent / "backtest.py"
    ret = subprocess.run(
        [sys.executable, str(backtest_script), "--min-backtest-periods", "100"],
        cwd=str(Path(__file__).parent),
    )
    if ret.returncode != 0:
        subprocess.run([sys.executable, str(backtest_script)], cwd=str(Path(__file__).parent))
    print("\n完成。")

if __name__ == "__main__":
    main()
