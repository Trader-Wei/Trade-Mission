# -*- coding: utf-8 -*-
"""
補齊歷史開獎樣本：從 twlottery.in 主頁 + 依日期 list 頁抓取，合併去重後寫入 data/bingobingo_history.csv。
目標至少 1220 期（供 1000 期回測）。執行後可再跑 train.py、backtest.py。
"""
import argparse
from pathlib import Path

from config import HISTORY_CSV
from data_sources import ensure_history_csv_full


def main():
    parser = argparse.ArgumentParser(description="補齊賓果賓果歷史開獎樣本（目標 1220+ 期）")
    parser.add_argument("--min-periods", type=int, default=1220, help="目標最少期數（預設 1220）")
    parser.add_argument("--days-back", type=int, default=400, help="依日期往回抓幾天（預設 400）")
    parser.add_argument("--out", type=str, default=None, help="輸出路徑（預設 data/bingobingo_history.csv）")
    args = parser.parse_args()
    out = Path(args.out) if args.out else HISTORY_CSV
    print(f"開始抓取歷史開獎，目標至少 {args.min_periods} 期，依日期往回 {args.days_back} 天…")
    path = ensure_history_csv_full(out_path=out, min_periods=args.min_periods, days_back=args.days_back)
    # 讀回筆數
    with open(path, "r", encoding="utf-8-sig") as f:
        n = sum(1 for _ in f) - 1
    print(f"已寫入 {path}，共 {n} 期。")
    if n >= args.min_periods:
        print("樣本已補齊，可執行: python train.py && python backtest.py")
    else:
        print(f"目前 {n} 期，未達目標 {args.min_periods} 期；若 twlottery.in 單頁僅約 200 期，可多日執行本腳本或手動提供更多歷史 CSV。")


if __name__ == "__main__":
    main()
