# -*- coding: utf-8 -*-
"""
簡易 API 伺服器：

- GET /api/update-history?max=500
  1) 從 twlottery.in 抓最新開獎，寫入 bingobingo_history.csv
  2) 再把 CSV 轉成 web/recent_draws.json（draws[0] = 最新）
  3) 回傳目前期數與檔案資訊

用途：讓前端按一下「更新開獎號碼」就能透過這個 API
      自動更新 EC2 上的 CSV + JSON，前端再載入 JSON 即可。
"""

from pathlib import Path
from typing import Optional
import sys

from flask import Flask, jsonify, request
from flask_cors import CORS

from bingobingo_bot.csv_to_recent_draws import convert

# 目前檔案所在目錄（bingobingo_bot）與專案根目錄
ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent
WEB_DIR = ROOT / "web"
JSON_PATH = WEB_DIR / "recent_draws.json"

# --- 機器學習預測模組（bingo_ml_predictor） ---
ML_ROOT = PROJECT_ROOT / "bingo_ml_predictor"
if str(ML_ROOT) not in sys.path:
    sys.path.insert(0, str(ML_ROOT))

from config import HISTORY_CSV as ML_HISTORY_CSV, MODEL_DIR  # type: ignore  # noqa: E402
from data_sources import ensure_history_csv_full  # type: ignore  # noqa: E402
from train import train_all  # type: ignore  # noqa: E402
from run_predict import run_predict  # type: ignore  # noqa: E402

CSV_PATH = ML_HISTORY_CSV  # 統一使用 ML 模組的歷史 CSV

app = Flask(__name__, static_folder=str(WEB_DIR), static_url_path="")
CORS(app)


@app.get("/")
def index():
    return app.send_static_file("index.html")


@app.get("/api/health")
def health():
    return jsonify({"ok": True})


@app.get("/api/update-history")
def update_history():
    max_draws: int = int(request.args.get("max", "500"))

    history_path = CSV_PATH
    warnings = []

    # 1) 盡量補齊歷史樣本到 ML 模組的 CSV（失敗時若已有舊檔，則退而使用舊檔）
    try:
        history_path = ensure_history_csv_full(
            out_path=CSV_PATH,
            min_periods=max(1220, max_draws) if max_draws > 0 else 1220,
            days_back=400,
        )
    except Exception as e:
        warnings.append(f"fetch_failed: {e}")
        if not Path(CSV_PATH).exists():
            # 既沒有網路也沒有舊檔，只能回報錯誤
            return jsonify({"ok": False, "error": "fetch_failed", "detail": str(e)}), 500
        history_path = CSV_PATH

    # 2) 僅在「尚未有模型檔」時才訓練一次 RF / XGB / 馬可夫，之後不再每次重訓（你要求的「固定參數」）
    train_info = None
    rf_path = MODEL_DIR / "rf_model.pkl"
    xgb_path = MODEL_DIR / "xgb_model.pkl"
    mk_path = MODEL_DIR / "markov_model.pkl"
    if not (rf_path.exists() and xgb_path.exists() and mk_path.exists()):
        try:
            train_info = train_all(csv_path=history_path)
        except Exception as e:
            warnings.append(f"train_failed: {e}")

    # 3) CSV → recent_draws.json（最新在前），供前端顯示歷史（失敗不影響預測回傳）
    try:
        convert(str(history_path), str(JSON_PATH), out_csv=None, max_draws=max_draws)
    except Exception as e:
        warnings.append(f"convert_failed: {e}")

    # 4) 執行一次 ML 預測（輸出 20 碼 + 3星/4星推薦）
    try:
        pred = run_predict()
    except Exception as e:
        return jsonify(
            {
                "ok": False,
                "error": "predict_failed",
                "detail": str(e),
                "warnings": warnings,
            }
        ), 500

    return jsonify(
        {
            "ok": True,
            "csv": str(Path(history_path).name),
            "json": str(JSON_PATH.name),
            "max": max_draws,
            "train": train_info,
            "prediction": pred,
            "warnings": warnings,
        }
    )


def main(host: str = "0.0.0.0", port: int = 8000) -> None:
    app.run(host=host, port=port)


if __name__ == "__main__":
    main()

