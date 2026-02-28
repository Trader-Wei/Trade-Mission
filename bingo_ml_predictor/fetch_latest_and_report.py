# -*- coding: utf-8 -*-
"""從 twlottery.in 抓取最新開獎，寫入 CSV 並在終端列出期號與開獎號碼。"""
import sys
import csv
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from data_sources import fetch_twlottery_history
from config import HISTORY_CSV

def main():
    print("正在從 twlottery.in 抓取最新開獎…")
    # 先試 twlottery（必要時延長逾時）
    import requests
    from config import URL_HISTORY
    from data_sources import _parse_draws_from_html
    try:
        r = requests.get(
            URL_HISTORY + "?_t=" + str(__import__("time").time()),
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"},
            timeout=25,
        )
        if r.ok:
            draws, periods = _parse_draws_from_html(r.text)
        else:
            draws, periods = [], []
    except Exception:
        draws, periods = [], []
    if not draws:
        draws, periods = fetch_twlottery_history(max_draws=0)
    if not draws:
        print("twlottery.in 無資料，改從 bingobingo_analysis.php 抓最新一期…")
        from data_sources import fetch_analysis_page
        nums, period, _ = fetch_analysis_page()
        if nums and period:
            draws = [sorted(nums)]
            periods = [period]
        else:
            from data_sources import fetch_rk_page
            nums2, period2 = fetch_rk_page()
            if nums2 and period2:
                draws = [sorted(nums2)]
                periods = [period2]
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
    report_path = Path(__file__).parent / "data" / "latest_draws_report.txt"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(f"已寫入 {HISTORY_CSV}，共 {len(draws)} 期（新→舊）。\n\n")
        f.write("=== 擷取的期號與開獎號碼（最新在前）===\n\n")
        for p, row in zip(periods, draws):
            nums_str = ", ".join(f"{n:02d}" for n in row)
            f.write(f"{p} | {nums_str}\n")
        f.write(f"\n共 {len(periods)} 期。\n")
    print(f"已寫入 {HISTORY_CSV}，共 {len(draws)} 期。報告: {report_path}")
    for p, row in zip(periods, draws):
        nums_str = ", ".join(f"{n:02d}" for n in row)
        print(f"{p} | {nums_str}")
    print(f"共 {len(periods)} 期。")

if __name__ == "__main__":
    main()
