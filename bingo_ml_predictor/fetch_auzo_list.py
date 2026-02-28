# -*- coding: utf-8 -*-
"""從奧索 list_YYYYMMDD.html 抓取當日開獎，寫入 CSV 並列出期號與開獎號碼。"""
import csv
import sys
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import HISTORY_CSV
from data_sources import fetch_auzo_list_page

def main():
    # 預設今天，可傳入 YYYYMMDD
    if len(sys.argv) > 1:
        date_str = sys.argv[1].replace("-", "")  # 2026-02-27 -> 20260227
    else:
        date_str = datetime.now().strftime("%Y%m%d")
    print(f"正在抓取 https://lotto.auzo.tw/bingobingo/list_{date_str}.html …")
    draws, periods = fetch_auzo_list_page(date_str)
    if not draws:
        print("解析不到任何一期開獎")
        return
    # 寫入 CSV（最舊→最新）
    draws_rev = list(reversed(draws))
    periods_rev = list(reversed(periods))
    HISTORY_CSV.parent.mkdir(parents=True, exist_ok=True)
    with open(HISTORY_CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["period"] + [f"n{i}" for i in range(1, 21)])
        for p, row in zip(periods_rev, draws_rev):
            w.writerow([p] + row)
    report_path = Path(__file__).parent / "data" / "auzo_draws_report.txt"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(f"已寫入 {HISTORY_CSV}，共 {len(draws)} 期（新→舊）。\n\n")
        f.write("=== 擷取的期號與開獎號碼（最新在前）===\n\n")
        for p, row in zip(periods, draws):
            nums_str = ", ".join(f"{n:02d}" for n in row)
            f.write(f"{p} | {nums_str}\n")
        f.write(f"\n共 {len(periods)} 期。\n")
    print(f"已寫入 {HISTORY_CSV}，共 {len(draws)} 期。報告: {report_path}\n")
    print("=== 擷取的期號與開獎號碼（最新在前）===\n")
    for p, row in zip(periods, draws):
        nums_str = ", ".join(f"{n:02d}" for n in row)
        print(f"{p} | {nums_str}")
    print(f"\n共 {len(periods)} 期。")

if __name__ == "__main__":
    main()
