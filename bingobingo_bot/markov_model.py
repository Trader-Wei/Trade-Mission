# -*- coding: utf-8 -*-
"""馬可夫鏈：依「上期該號是否開出」估計「本期該號開出」的機率。"""

import numpy as np

NUM_RANGE = 80


class MarkovBingo:
    """
    簡化馬可夫：對每個號碼 n，估計
    P(本期開出 | 上期有開出) 與 P(本期開出 | 上期沒開出)。
    依上期狀態給出本期 1~80 的出現機率。
    """

    def __init__(self):
        self.p_given_yes = np.full(NUM_RANGE, 0.25)  # 上期有 -> 本期出現機率
        self.p_given_no = np.full(NUM_RANGE, 0.25)   # 上期無 -> 本期出現機率
        self.fitted = False

    def fit(self, mat: np.ndarray):
        """
        mat: (T, 80) 每期 0/1
        估計每個號碼的轉移機率。
        """
        count_yes_next_yes = np.zeros(NUM_RANGE)
        count_yes_next_no = np.zeros(NUM_RANGE)
        count_no_next_yes = np.zeros(NUM_RANGE)
        count_no_next_no = np.zeros(NUM_RANGE)

        for t in range(1, mat.shape[0]):
            prev = mat[t - 1]
            curr = mat[t]
            for n in range(NUM_RANGE):
                if prev[n] == 1:
                    if curr[n] == 1:
                        count_yes_next_yes[n] += 1
                    else:
                        count_yes_next_no[n] += 1
                else:
                    if curr[n] == 1:
                        count_no_next_yes[n] += 1
                    else:
                        count_no_next_no[n] += 1

        for n in range(NUM_RANGE):
            yes_total = count_yes_next_yes[n] + count_yes_next_no[n]
            no_total = count_no_next_yes[n] + count_no_next_no[n]
            if yes_total > 0:
                self.p_given_yes[n] = count_yes_next_yes[n] / yes_total
            if no_total > 0:
                self.p_given_no[n] = count_no_next_yes[n] / no_total

        self.fitted = True
        return self

    def predict_proba(self, last_draw: np.ndarray) -> np.ndarray:
        """
        last_draw: (80,) 上期 0/1
        回傳 (80,) 本期各號碼「開出」的機率。
        """
        p = np.where(last_draw == 1, self.p_given_yes, self.p_given_no)
        return p.astype(np.float64)
