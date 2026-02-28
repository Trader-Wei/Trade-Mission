# -*- coding: utf-8 -*-
"""
從官方或自備的歷史開獎 CSV 產生
1) 給回測 / 學習用的 CSV（選擇性）
2) 給網頁用的 recent_draws.json（必須，draws[0]=最新一期）

用途：完全不爬網站，只做「你下載好的 CSV → 標準格式」的轉換，確保號碼正確。
"""

import json
import sys
from pathlib import Path

from bingobingo_bot.data_loader import load_history_csv


def convert(csv_path: str, out_json: str, out_csv: str | None = None, max_draws: int = 0) -> None:
    src = Path(csv_path)
    if not src.exists():
        raise SystemExit(f"找不到 CSV 檔：{src}")

    df = load_history_csv(str(src))
    # df 順序：原始檔的順序，通常為「舊→新」
    # 轉成 list-of-lists，並反轉成「新→舊」給網頁使用
    numbers_only = df[[f"n{i}" for i in range(1, 21)]].to_numpy().tolist()
    numbers_only = [list(map(int, row)) for row in numbers_only]
    numbers_only.reverse()  # 0 = 最新

    if max_draws > 0 and len(numbers_only) > max_draws:
        numbers_only = numbers_only[:max_draws]

    out_json_path = Path(out_json)
    out_json_path.parent.mkdir(parents=True, exist_ok=True)
    with out_json_path.open("w", encoding="utf-8") as f:
        json.dump(numbers_only, f, ensure_ascii=False)
    print(f"已寫入網頁用 JSON {len(numbers_only)} 期 → {out_json_path}")

    if out_csv:
        out_csv_path = Path(out_csv)
        out_csv_path.parent.mkdir(parents=True, exist_ok=True)
        # 直接用 load_history_csv 後的格式輸出（period + n1..n20），保留原本「舊→新」順序
        df.to_csv(out_csv_path, index=False, encoding="utf-8-sig")
        print(f"已寫入標準 CSV → {out_csv_path}")


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="從歷史開獎 CSV 產生 recent_draws.json（給網頁用）")
    parser.add_argument("--csv", required=True, help="歷史開獎 CSV 路徑（官方下載或自備皆可）")
    parser.add_argument(
        "--out-json",
        default="bingobingo_bot/web/recent_draws.json",
        help="輸出給網頁用的 JSON 路徑（預設 bingobingo_bot/web/recent_draws.json）",
    )
    parser.add_argument(
        "--out-csv",
        default=None,
        help="（選用）同時輸出一份標準化 CSV 路徑；若不需可略過",
    )
    parser.add_argument(
        "--max",
        type=int,
        default=0,
        help="最多保留期數（0=全部；500 代表只留最近 500 期）",
    )
    args = parser.parse_args()

    convert(args.csv, args.out_json, args.out_csv, max_draws=args.max)
    return 0


if __name__ == "__main__":
    sys.exit(main())

