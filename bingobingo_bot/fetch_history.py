# -*- coding: utf-8 -*-
"""
從 twlottery.in 抓取賓果賓果真實歷史開獎，存成 CSV。
CSV 格式：period,n1,n2,...,n20（第一行=最舊期，最後一行=最新期），供 backtest / tune_backtest 使用。
"""

import re
import sys
import csv
from pathlib import Path

try:
    import requests
except ImportError:
    print("請安裝 requests: pip install requests")
    sys.exit(1)

URL = "https://twlottery.in/lotteryBingo"
NUM_PER_DRAW = 20
NUM_RE = re.compile(r"\b(?:[1-9]|[1-7]\d|80)\b")
BLOCK_RE = re.compile(
    r"(\d{8,})\s*期\s*([\s\S]*?)(?=\d{8,}\s*期|$)",
    re.IGNORECASE,
)


def parse_draws_from_html(html: str):
    """
    解析 HTML，回傳 (draws, periods)。
    draws[i] = 該期 20 個號碼（由小到大），頁面順=新→舊。
    periods[i] = 期別字串。
    """
    draws = []
    periods = []
    for m in BLOCK_RE.finditer(html):
        period = m.group(1)
        block = m.group(2)
        seen = set()
        nums = []
        for num_m in NUM_RE.finditer(block):
            if len(nums) >= NUM_PER_DRAW:
                break
            n = int(num_m.group(0))
            if 1 <= n <= 80 and n not in seen:
                seen.add(n)
                nums.append(n)
        if len(nums) == NUM_PER_DRAW:
            draws.append(sorted(nums))
            periods.append(period)
    if draws:
        return draws, periods
    # 備援：用期別位置切區塊
    period_matches = list(re.finditer(r"\d{8,}", html))
    for k in range(len(period_matches) - 1):
        start = period_matches[k].end()
        end = period_matches[k + 1].start()
        if end - start < 50:
            continue
        seg = html[start:end]
        seen = set()
        nums = []
        for num_m in NUM_RE.finditer(seg):
            if len(nums) >= NUM_PER_DRAW:
                break
            n = int(num_m.group(0))
            if 1 <= n <= 80 and n not in seen:
                seen.add(n)
                nums.append(n)
        if len(nums) == NUM_PER_DRAW:
            draws.append(sorted(nums))
            periods.append(period_matches[k].group(0))
    if not periods and period_matches:
        periods = [period_matches[0].group(0)] * len(draws)
    return draws, periods


def fetch_and_save_csv(out_path: str, max_draws: int = 0):
    """
    抓取開獎頁並存成 CSV。
    out_path: 輸出 CSV 路徑。
    max_draws: 最多保留幾期（0=全部）。CSV 內順序：最舊→最新（符合 backtest 約定）。
    """
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    try:
        r = requests.get(URL, headers=headers, timeout=15)
        r.raise_for_status()
        html = r.text
    except Exception as e:
        print(f"抓取失敗: {e}")
        return False
    draws, periods = parse_draws_from_html(html)
    if not draws:
        print("解析不到任何一期開獎")
        return False
    # 頁面順=新→舊，要存成最舊→最新
    draws = list(reversed(draws))
    periods = list(reversed(periods))
    if max_draws > 0 and len(draws) > max_draws:
        draws = draws[-max_draws:]
        periods = periods[-max_draws:]
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["period"] + [f"n{i}" for i in range(1, 21)])
        for p, row in zip(periods, draws):
            w.writerow([p] + row)
    print(f"已寫入 {len(draws)} 期 → {out}")
    return True


def main():
    import argparse
    parser = argparse.ArgumentParser(description="從 twlottery.in 抓取賓果賓果歷史開獎並存成 CSV")
    parser.add_argument("-o", "--out", type=str, default="bingobingo_history.csv", help="輸出 CSV 路徑")
    parser.add_argument("--max", type=int, default=0, help="最多保留期數（0=全部）")
    args = parser.parse_args()
    ok = fetch_and_save_csv(args.out, max_draws=args.max)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
