# -*- coding: utf-8 -*-
"""
Bingo Bingo 預測 Bot 主程式：
1. 從 RK.php、bingobingo_analysis.php 與本地歷史取得/更新數據
2. 載入已訓練的 RF / XGB / 馬可夫模型（若無則先訓練）
3. 輸出下期預測 20 碼與加權分數（可調參數與權重見 config.py）
"""
import pickle
import sys
from pathlib import Path

from config import DATA_DIR, HISTORY_CSV, MODEL_DIR, LOOKBACK, get_weights
from data_sources import (
    load_history_dataframe,
    ensure_history_csv,
    fetch_analysis_page,
    fetch_rk_page,
)
from features import draws_to_matrix
from ensemble import predict_next_20, predict_next_20_by_score_order


def load_models():
    rf_path = MODEL_DIR / "rf_model.pkl"
    xgb_path = MODEL_DIR / "xgb_model.pkl"
    markov_path = MODEL_DIR / "markov_model.pkl"
    meta_path = MODEL_DIR / "meta.pkl"
    if not rf_path.exists() or not xgb_path.exists() or not markov_path.exists():
        return None, None, None, None
    with open(rf_path, "rb") as f:
        rf = pickle.load(f)
    with open(xgb_path, "rb") as f:
        xgb = pickle.load(f)
    with open(markov_path, "rb") as f:
        markov = pickle.load(f)
    meta = {}
    if meta_path.exists():
        with open(meta_path, "rb") as f:
            meta = pickle.load(f)
    return rf, xgb, markov, meta


def run_predict(
    use_analysis_page: bool = True,
    use_rk_page: bool = True,
    weight_rf: float = None,
    weight_xgb: float = None,
    weight_markov: float = None,
) -> dict:
    """
    執行一次預測。呼叫前請先用 train.py 訓練好模型。
    """
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    # 可選：從分析頁 / RK 取得「最新一期」對照（不影響預測模型，僅供顯示）
    latest_from_web = None
    if use_analysis_page:
        nums, period, _ = fetch_analysis_page()
        if nums:
            latest_from_web = {"source": "bingobingo_analysis.php", "period": period, "numbers": nums}
    if latest_from_web is None and use_rk_page:
        nums, period = fetch_rk_page()
        if nums:
            latest_from_web = {"source": "RK.php", "period": period, "numbers": nums}

    # 載入歷史與模型
    if not HISTORY_CSV.exists():
        ensure_history_csv()
    df = load_history_dataframe()
    mat = draws_to_matrix(df)
    T = mat.shape[0]
    lookback = LOOKBACK

    rf, xgb, markov, meta = load_models()
    if meta:
        lookback = meta.get("lookback", LOOKBACK)
    if rf is None or xgb is None or markov is None:
        return {
            "error": "尚未訓練模型，請先執行: python train.py",
            "latest_from_web": latest_from_web,
        }

    # 預測「下一期」（以目前最後一期為上期）
    p_rf = rf.predict_proba(mat, T - 1, lookback=lookback)
    p_xgb = xgb.predict_proba(mat, T - 1, lookback=lookback)
    last_draw = mat[T - 1]
    p_markov = markov.predict_proba(last_draw)

    w_rf, w_xgb, w_markov = get_weights()
    if weight_rf is not None:
        w_rf, w_xgb, w_markov = weight_rf, weight_xgb, weight_markov
        total = w_rf + w_xgb + w_markov
        w_rf, w_xgb, w_markov = w_rf / total, w_xgb / total, w_markov / total

    # 20 碼預測（排序）及依分數高低排序，用於 3 星 / 4 星推薦
    pred_20 = predict_next_20(p_rf, p_xgb, p_markov, w_rf, w_xgb, w_markov)
    ordered_20 = predict_next_20_by_score_order(
        p_rf, p_xgb, p_markov, w_rf, w_xgb, w_markov
    )
    top3 = ordered_20[:3]
    top4 = ordered_20[:4]

    # 若能取得目前最新期數，推算下一期期號（+1）供前端顯示
    predicted_period = None
    if latest_from_web and latest_from_web.get("period"):
        try:
            predicted_period = str(int(str(latest_from_web["period"]).strip()) + 1)
        except Exception:
            predicted_period = None

    return {
        "predicted_numbers": pred_20,
        "ordered_numbers": ordered_20,
        "top3": top3,
        "top4": top4,
        "predicted_period": predicted_period,
        "weights_used": {"rf": w_rf, "xgb": w_xgb, "markov": w_markov},
        "n_periods_used": T,
        "latest_from_web": latest_from_web,
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Bingo Bingo 下期預測（RF+XGB+馬可夫）")
    parser.add_argument("--no-analysis", action="store_true", help="不抓 bingobingo_analysis.php")
    parser.add_argument("--no-rk", action="store_true", help="不抓 RK.php")
    parser.add_argument("--wr", type=float, default=None, help="RF 權重")
    parser.add_argument("--wx", type=float, default=None, help="XGB 權重")
    parser.add_argument("--wm", type=float, default=None, help="馬可夫權重")
    args = parser.parse_args()
    res = run_predict(
        use_analysis_page=not args.no_analysis,
        use_rk_page=not args.no_rk,
        weight_rf=args.wr,
        weight_xgb=args.wx,
        weight_markov=args.wm,
    )
    if res.get("error"):
        print(res["error"], file=sys.stderr)
        if res.get("latest_from_web"):
            print("網頁最新一期:", res["latest_from_web"])
        sys.exit(1)
    print("下期預測 20 碼:", res["predicted_numbers"])
    print("權重:", res["weights_used"])
    if res.get("latest_from_web"):
        print("參考（網頁最新）:", res["latest_from_web"].get("period"), res["latest_from_web"].get("numbers"))
    return res


if __name__ == "__main__":
    main()
