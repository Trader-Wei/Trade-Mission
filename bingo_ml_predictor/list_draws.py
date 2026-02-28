# -*- coding: utf-8 -*-
"""列出目前抓到的期號與開獎號碼。"""
import pandas as pd
from pathlib import Path

path = Path(__file__).parent / "data" / "bingobingo_history.csv"
df = pd.read_csv(path, encoding="utf-8-sig")
cols = ["period"] + [f"n{i}" for i in range(1, 21)]
df = df[cols].drop_duplicates()
df = df.sort_values("period")
df["period"] = df["period"].astype(str)
# 排除異常期號（台彩期號約 8~9 碼，排除 10 碼以上）
df["period"] = df["period"].astype(str).str.strip()
df = df[df["period"].str.match(r"^\d{8,9}$", na=False)]

print(f"共 {len(df)} 期（去重後）\n")
for _, row in df.iterrows():
    nums = [int(row[f"n{j}"]) for j in range(1, 21)]
    nums_str = ", ".join(f"{n:02d}" for n in nums)
    print(f"{row['period']} | {nums_str}")
