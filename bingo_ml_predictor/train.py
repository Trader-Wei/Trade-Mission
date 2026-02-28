# -*- coding: utf-8 -*-
"""
載入真實歷史數據，訓練 RF / XGB / 馬可夫鏈，並儲存模型供預測與回測使用。
"""
import pickle
import numpy as np
from pathlib import Path

from config import LOOKBACK, MIN_TRAIN_ROWS, MODEL_DIR, HISTORY_CSV
from data_sources import load_history_dataframe, ensure_history_csv
from features import draws_to_matrix
from model_rf import RFBingoModel
from model_xgb import XGBBingoModel
from model_markov import MarkovModel


def train_all(
    csv_path: Path = None,
    lookback: int = LOOKBACK,
    save_dir: Path = None,
) -> dict:
    """
    1. 確保有歷史 CSV（若無則抓取）
    2. 載入並轉成 mat
    3. 訓練 RF、XGB、Markov
    4. 儲存到 save_dir
    """
    save_dir = Path(save_dir or MODEL_DIR)
    save_dir.mkdir(parents=True, exist_ok=True)
    csv_path = csv_path or HISTORY_CSV
    if not csv_path.exists():
        ensure_history_csv(csv_path)
    df = load_history_dataframe(csv_path)
    mat = draws_to_matrix(df)
    if mat.shape[0] < MIN_TRAIN_ROWS:
        raise ValueError(f"歷史期數至少需 {MIN_TRAIN_ROWS} 期，目前 {mat.shape[0]} 期")

    rf = RFBingoModel()
    rf.fit(mat, lookback=lookback)
    xgb = XGBBingoModel()
    xgb.fit(mat, lookback=lookback)
    markov = MarkovModel()
    markov.fit(mat)

    with open(save_dir / "rf_model.pkl", "wb") as f:
        pickle.dump(rf, f)
    with open(save_dir / "xgb_model.pkl", "wb") as f:
        pickle.dump(xgb, f)
    with open(save_dir / "markov_model.pkl", "wb") as f:
        pickle.dump(markov, f)
    with open(save_dir / "meta.pkl", "wb") as f:
        pickle.dump({"lookback": lookback, "n_periods": mat.shape[0]}, f)

    return {
        "lookback": lookback,
        "n_periods": mat.shape[0],
        "saved": [str(save_dir / "rf_model.pkl"), str(save_dir / "xgb_model.pkl"), str(save_dir / "markov_model.pkl")],
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="訓練 Bingo 預測模型（RF+XGB+馬可夫）")
    parser.add_argument("--csv", type=str, default=None)
    parser.add_argument("--lookback", type=int, default=LOOKBACK)
    parser.add_argument("--out-dir", type=str, default=None)
    args = parser.parse_args()
    csv_path = Path(args.csv) if args.csv else None
    out_dir = Path(args.out_dir) if args.out_dir else None
    info = train_all(csv_path=csv_path, lookback=args.lookback, save_dir=out_dir)
    print("訓練完成:", info)


if __name__ == "__main__":
    main()
