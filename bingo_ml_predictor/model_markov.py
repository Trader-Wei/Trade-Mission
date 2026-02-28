# -*- coding: utf-8 -*-
"""
馬可夫鏈：依「上期該號是否開出」估計「本期該號開出」的轉移機率。
"""
import numpy as np
from config import NUM_RANGE


class MarkovModel:
    """
    對每個號碼 n，估計：
    P(本期開出 | 上期有開出)、P(本期開出 | 上期沒開出)。
    依上期狀態給出本期 1~80 的出現機率。
    """

    def __init__(self):
        self.p_given_yes = np.full(NUM_RANGE, 0.25)
        self.p_given_no = np.full(NUM_RANGE, 0.25)
        self.fitted = False

    def fit(self, mat: np.ndarray) -> "MarkovModel":
        """mat: (T, 80) 每期 0/1。"""
        count_yy = np.zeros(NUM_RANGE)
        count_yn = np.zeros(NUM_RANGE)
        count_ny = np.zeros(NUM_RANGE)
        count_nn = np.zeros(NUM_RANGE)
        for t in range(1, mat.shape[0]):
            prev, curr = mat[t - 1], mat[t]
            for n in range(NUM_RANGE):
                if prev[n] == 1:
                    if curr[n] == 1:
                        count_yy[n] += 1
                    else:
                        count_yn[n] += 1
                else:
                    if curr[n] == 1:
                        count_ny[n] += 1
                    else:
                        count_nn[n] += 1
        for n in range(NUM_RANGE):
            yes_tot = count_yy[n] + count_yn[n]
            no_tot = count_ny[n] + count_nn[n]
            if yes_tot > 0:
                self.p_given_yes[n] = count_yy[n] / yes_tot
            if no_tot > 0:
                self.p_given_no[n] = count_ny[n] / no_tot
        self.fitted = True
        return self

    def predict_proba(self, last_draw: np.ndarray) -> np.ndarray:
        """last_draw: (80,) 上期 0/1。回傳 (80,) 本期各號開出機率。"""
        proba = np.where(last_draw == 1, self.p_given_yes, self.p_given_no)
        return proba.astype(np.float32)
