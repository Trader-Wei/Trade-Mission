# -*- coding: utf-8 -*-
"""
從指定網頁與歷史來源載入真實 Bingo Bingo 數據。
- RK.php（若可連）
- bingobingo_analysis.php（解析當期與統計）
- twlottery.in 歷史開獎（供回測與訓練）
"""
import re
import csv
import time
from pathlib import Path
from typing import List, Optional, Tuple

import requests
import pandas as pd

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

from config import (
    URL_RK,
    URL_ANALYSIS,
    URL_HISTORY,
    URL_HISTORY_LIST,
    URL_AUZO_LIST,
    DATA_DIR,
    HISTORY_CSV,
    NUM_RANGE,
    DRAW_SIZE,
)

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
REQUEST_TIMEOUT = 12
NUM_PER_DRAW = DRAW_SIZE


def _get(url: str) -> Optional[str]:
    try:
        r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        return r.text
    except Exception:
        return None


def _extract_list_numbers_from_html(block: str) -> List[int]:
    """從 HTML 區塊擷取「- 數字」或表格內的 1~80 號碼，最多 20 個不重複。"""
    seen = set()
    nums = []
    # 常見格式：- 03 或 <td>03</td> 或 03 04 06 ...
    for m in re.finditer(r"\b(\d{1,2})\b", block):
        n = int(m.group(1))
        if 1 <= n <= NUM_RANGE and n not in seen:
            seen.add(n)
            nums.append(n)
            if len(nums) >= NUM_PER_DRAW:
                break
    return nums


def fetch_analysis_page() -> Tuple[Optional[List[int]], Optional[str], dict]:
    """
    抓取 bingobingo_analysis.php。
    回傳: (當期 20 碼, 期數字串, 額外統計 dict)。
    """
    html = _get(URL_ANALYSIS)
    if not html:
        return None, None, {}

    extra = {}
    period = None
    # 期數如 115011770 23:35
    period_m = re.search(r"(\d{8,})\s*\d{2}:\d{2}", html)
    if period_m:
        period = period_m.group(1).strip()

    # 優先從表格/結構化區塊取 20 個號碼（常見為兩行 10+10）
    if BeautifulSoup:
        try:
            soup = BeautifulSoup(html, "html.parser")
            cells = soup.find_all(["td", "span"])
            cands = []
            for c in cells:
                t = (c.get_text() or "").strip()
                if t.isdigit() and 1 <= int(t) <= NUM_RANGE:
                    cands.append(int(t))
            seen = set()
            nums = []
            for n in cands:
                if n not in seen:
                    seen.add(n)
                    nums.append(n)
                    if len(nums) >= NUM_PER_DRAW:
                        break
            if len(nums) == NUM_PER_DRAW:
                return sorted(nums), period, extra
        except Exception:
            pass

    # 備援：正則從整頁取連續 20 個 1~80 不重複
    nums = _extract_list_numbers_from_html(html)
    if len(nums) >= NUM_PER_DRAW:
        return sorted(nums[:NUM_PER_DRAW]), period, extra
    return None, period, extra


def fetch_rk_page() -> Tuple[Optional[List[int]], Optional[str]]:
    """
    抓取 RK.php，嘗試解析當期 20 碼與期數。
    若逾時或解析失敗回傳 (None, None)。
    """
    html = _get(URL_RK)
    if not html:
        return None, None
    period_m = re.search(r"(\d{8,})", html)
    period = period_m.group(1) if period_m else None
    nums = _extract_list_numbers_from_html(html)
    if len(nums) >= NUM_PER_DRAW:
        return sorted(nums[:NUM_PER_DRAW]), period
    return None, period


def fetch_twlottery_history(max_draws: int = 0) -> Tuple[List[List[int]], List[str]]:
    """
    從 twlottery.in 抓取歷史開獎（與現有 fetch_history 邏輯一致，此處獨立實作）。
    回傳 (draws, periods)，draws 每項為 20 個號碼 sorted，順序為 新→舊。
    """
    url = URL_HISTORY + "?_t=" + str(time.time())
    html = _get(url)
    if not html:
        return [], []

    block_re = re.compile(
        r"(\d{8,})\s*期\s*([\s\S]*?)(?=\d{8,}\s*期|$)",
        re.IGNORECASE,
    )
    list_num_re = re.compile(r"-\s*(\d{1,2})\b")

    def extract(block: str) -> List[int]:
        seen = set()
        nums = []
        for m in list_num_re.finditer(block):
            if len(nums) >= NUM_PER_DRAW:
                break
            n = int(m.group(1))
            if 1 <= n <= NUM_RANGE and n not in seen:
                seen.add(n)
                nums.append(n)
        return nums

    draws = []
    periods = []
    for m in block_re.finditer(html):
        period = m.group(1)
        block = m.group(2)
        nums = extract(block)
        if len(nums) == NUM_PER_DRAW:
            draws.append(sorted(nums))
            periods.append(period)
    if not draws and re.findall(r"\d{8,}", html):
        # 備援：依期號切區塊
        period_matches = list(re.finditer(r"\d{8,}", html))
        for k in range(len(period_matches) - 1):
            start, end = period_matches[k].end(), period_matches[k + 1].start()
            if end - start < 50:
                continue
            nums = extract(html[start:end])
            if len(nums) == NUM_PER_DRAW:
                draws.append(sorted(nums))
                periods.append(period_matches[k].group(0))

    if max_draws > 0 and len(draws) > max_draws:
        draws = draws[:max_draws]
        periods = periods[:max_draws]
    return draws, periods


def _parse_draws_from_html(html: str) -> Tuple[List[List[int]], List[str]]:
    """共用解析：從 HTML 擷取「期號 + 20 碼」區塊，回傳 (draws, periods) 新→舊。"""
    block_re = re.compile(
        r"(\d{8,})\s*期\s*([\s\S]*?)(?=\d{8,}\s*期|$)",
        re.IGNORECASE,
    )
    list_num_re = re.compile(r"-\s*(\d{1,2})\b")
    draws = []
    periods = []
    for m in block_re.finditer(html):
        period = m.group(1)
        block = m.group(2)
        seen = set()
        nums = []
        for mm in list_num_re.finditer(block):
            if len(nums) >= NUM_PER_DRAW:
                break
            n = int(mm.group(1))
            if 1 <= n <= NUM_RANGE and n not in seen:
                seen.add(n)
                nums.append(n)
        if len(nums) == NUM_PER_DRAW:
            draws.append(sorted(nums))
            periods.append(period)
    return draws, periods


def fetch_auzo_list_page(date_str: str) -> Tuple[List[List[int]], List[str]]:
    """
    從奧索樂透網當日列表抓取：https://lotto.auzo.tw/bingobingo/list_YYYYMMDD.html
    date_str 格式 YYYYMMDD（如 20260227）。回傳 (draws, periods) 新→舊。
    """
    url = URL_AUZO_LIST.format(date=date_str)
    html = _get(url)
    if not html:
        return [], []
    # 1) 期號：115011XXX 去重且保持出現順序（新→舊）
    period_re = re.compile(r"115011\d{3}")
    periods = []
    seen = set()
    for m in period_re.finditer(html):
        if m.group(0) not in seen:
            seen.add(m.group(0))
            periods.append(m.group(0))
    # 2) 開獎號碼：HTML 內為 >06< >11< ... 每 20 個一組，擷取所有 >N< 依序再取每段 20 碼合法區塊
    num_re = re.compile(r">(\d{1,2})<")
    all_nums = [int(m.group(1)) for m in num_re.finditer(html)]
    draws = []
    i = 0
    while i + 20 <= len(all_nums):
        block = all_nums[i : i + 20]
        if all(1 <= n <= NUM_RANGE for n in block) and len(set(block)) == 20:
            draws.append(sorted(block))
            i += 20
        else:
            i += 1
    # 期數與筆數對齊（頁面上一期對一組 20 碼）
    if len(periods) > len(draws):
        periods = periods[: len(draws)]
    elif len(draws) > len(periods):
        draws = draws[: len(periods)]
    if not periods and draws:
        periods = [f"{date_str}{j:04d}" for j in range(len(draws))]
    return draws, periods


def fetch_twlottery_by_date(date_str: str) -> Tuple[List[List[int]], List[str]]:
    """
    從 twlottery.in 依日期抓取當日開獎。date_str 格式 YYYY-MM-DD。
    回傳 (draws, periods)，若該頁無資料則 ([], [])。
    """
    url = URL_HISTORY_LIST + date_str
    html = _get(url)
    if not html:
        return [], []
    return _parse_draws_from_html(html)


def ensure_history_csv_full(
    out_path: Optional[Path] = None,
    min_periods: int = 1220,
    days_back: int = 400,
) -> Path:
    """
    盡量補齊樣本：先抓主頁，再依日期逐日抓 list 頁，合併去重後寫入 CSV。
    目標至少 min_periods 期（預設 1220，供 1000 期回測）。
    """
    out_path = Path(out_path or HISTORY_CSV)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # 1) 主頁（一次取得較多期）
    draws_main, periods_main = fetch_twlottery_history(max_draws=0)
    by_period = {}
    for p, row in zip(periods_main, draws_main):
        by_period[p] = row

    # 2) 依日期抓 list 頁（補齊更早的期數，達目標可提早結束）
    from datetime import datetime, timedelta
    today = datetime.now().date()
    for i in range(days_back):
        if len(by_period) >= min_periods:
            break
        d = today - timedelta(days=i)
        date_str = d.strftime("%Y-%m-%d")
        draws_d, periods_d = fetch_twlottery_by_date(date_str)
        for p, row in zip(periods_d, draws_d):
            if p not in by_period:
                by_period[p] = row
        time.sleep(0.35)

    if not by_period:
        if out_path.exists():
            return out_path
        raise FileNotFoundError("無法取得任何歷史開獎，請稍後再試。")

    # 3) 依期號排序（最舊→最新），寫入 CSV
    sorted_periods = sorted(by_period.keys(), key=lambda x: int(x))
    rows = [(p, by_period[p]) for p in sorted_periods]
    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["period"] + [f"n{i}" for i in range(1, 21)])
        for p, row in rows:
            w.writerow([p] + row)
    return out_path


def ensure_history_csv(out_path: Optional[Path] = None, max_draws: int = 0) -> Path:
    """
    若本地無 CSV 或需要更新，則從 twlottery.in 抓取並寫入 CSV。
    CSV 格式：period, n1..n20，最舊→最新（供回測）。
    """
    out_path = out_path or HISTORY_CSV
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    draws, periods = fetch_twlottery_history(max_draws=max_draws)
    if not draws:
        if out_path.exists():
            return out_path
        raise FileNotFoundError("無法取得歷史開獎且本地無 CSV，請稍後再試或手動提供 CSV。")

    # 寫入：最舊→最新
    draws_rev = list(reversed(draws))
    periods_rev = list(reversed(periods))
    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["period"] + [f"n{i}" for i in range(1, 21)])
        for p, row in zip(periods_rev, draws_rev):
            w.writerow([p] + row)
    return out_path


def load_history_dataframe(csv_path: Optional[Path] = None) -> pd.DataFrame:
    """載入歷史 CSV 為 DataFrame，欄位 period, n1..n20。"""
    path = Path(csv_path or HISTORY_CSV)
    if not path.exists():
        ensure_history_csv(path)
    df = pd.read_csv(path, encoding="utf-8-sig")
    # 標準欄位：period, n1..n20
    want = [f"n{i}" for i in range(1, 21)]
    if "period" in df.columns and all(c in df.columns for c in want):
        return df[["period"] + want].copy()
    num_cols = [c for c in df.columns if re.match(r"^n\d+$", str(c).strip())]
    num_cols = sorted(num_cols, key=lambda x: int(re.search(r"\d+", x).group()))
    if len(num_cols) < 20:
        num_cols = [c for c in df.columns if c != "period" and pd.api.types.is_numeric_dtype(df[c])][:20]
    num_cols = num_cols[:20]
    out = pd.DataFrame()
    if "period" in df.columns:
        out["period"] = df["period"]
    else:
        out["period"] = range(len(df))
    for i, c in enumerate(num_cols):
        out[f"n{i + 1}"] = df[c].values
    return out
