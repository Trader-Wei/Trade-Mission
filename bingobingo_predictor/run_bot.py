# -*- coding: utf-8 -*-
"""
賓果賓果預測 Bot：隨機森林 + XGBoost + 馬可夫鏈預測當期號碼。
使用方式：
  python run_bot.py                    # 使用內建模擬資料示範
  python run_bot.py --csv 歷史開獎.csv  # 使用自有 CSV 歷史開獎
  python run_bot.py --csv 歷史開獎.csv --lookback 150
"""

import argparse
import sys
from pathlib import Path

# 從專案根目錄執行：python -m bingobingo_predictor.run_bot
# 或進入 bingobingo_predictor 後：python run_bot.py（會把上層加入 path 並以套件載入）
_root = Path(__file__).resolve().parent
_parent = _root.parent
if _parent not in sys.path:
    sys.path.insert(0, str(_parent))
from bingobingo_predictor.predictor import BingobingoPredictor, run_from_csv, run_with_sample_data


def main():
    parser = argparse.ArgumentParser(description="賓果賓果當期號碼預測 Bot（RF + XGBoost + 馬可夫鏈）")
    parser.add_argument("--csv", type=str, default=None, help="歷史開獎 CSV 路徑（無則用模擬資料）")
    parser.add_argument("--lookback", type=int, default=100, help="特徵回溯期數（預設 100）")
    parser.add_argument("--draws", type=int, default=500, help="模擬資料期數（僅在未給 --csv 時使用）")
    parser.add_argument("--seed", type=int, default=42, help="模擬資料亂數種子")
    parser.add_argument("--super", action="store_true", help="一併輸出超級獎號預測")
    parser.add_argument("--top", type=int, default=None, help="只輸出前 N 個最容易出現的號碼（例如 3）")
    args = parser.parse_args()

    if args.csv and Path(args.csv).exists():
        print(f"從 CSV 載入歷史開獎: {args.csv}")
        predictor = run_from_csv(args.csv, lookback=args.lookback)
    else:
        if args.csv:
            print(f"找不到檔案 {args.csv}，改用模擬資料。")
        print(f"使用模擬歷史開獎（{args.draws} 期）訓練...")
        predictor = run_with_sample_data(num_draws=args.draws, lookback=args.lookback, seed=args.seed)

    if args.top is not None and args.top > 0:
        top_n = predictor.predict_current_draw(top_k=min(args.top, 20))
        print("最容易出現的 {} 個號碼: {}".format(len(top_n), top_n.tolist()))
    elif args.super:
        main_20, super_num = predictor.predict_with_super()
        print("預測當期 20 個號碼（主獎）:", main_20.tolist())
        print("預測超級獎號:", super_num)
    else:
        current = predictor.predict_current_draw()
        print("預測當期 20 個號碼:", current.tolist())

    print("（此為模型推估，僅供參考，請勿作為投注唯一依據。）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
