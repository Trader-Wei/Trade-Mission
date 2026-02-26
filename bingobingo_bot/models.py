# -*- coding: utf-8 -*-
"""Random Forest + XGBoost 預測各號碼當期是否開出。"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
import xgboost as xgb

NUM_RANGE = 80
DRAW_SIZE = 20


class RFXGBEnsemble:
    """
    用「特徵矩陣」訓練 RF 與 XGBoost，預測每個號碼當期是否開出；
    預測時輸出 1~80 的「出現機率」。
    """

    def __init__(self, rf_params=None, xgb_params=None):
        self.rf_params = rf_params or {"n_estimators": 150, "max_depth": 8, "random_state": 42}
        self.xgb_params = xgb_params or {
            "n_estimators": 150,
            "max_depth": 6,
            "learning_rate": 0.1,
            "random_state": 42,
        }
        self.scaler = StandardScaler()
        self.rf = RandomForestClassifier(**self.rf_params)
        self.xgb_clf = None
        self.fitted = False

    def fit(self, X: np.ndarray, y: np.ndarray):
        """
        X: (N, n_features), y: (N,) 0/1
        """
        X_scaled = self.scaler.fit_transform(X)
        self.rf.fit(X_scaled, y)
        self.xgb_clf = xgb.XGBClassifier(**self.xgb_params)
        self.xgb_clf.fit(X_scaled, y)
        self.fitted = True
        return self

    def predict_proba_rf(self, X: np.ndarray) -> np.ndarray:
        """回傳 (N,) 為「正類」機率。"""
        X_scaled = self.scaler.transform(X)
        return self.rf.predict_proba(X_scaled)[:, 1]

    def predict_proba_xgb(self, X: np.ndarray) -> np.ndarray:
        X_scaled = self.scaler.transform(X)
        return self.xgb_clf.predict_proba(X_scaled)[:, 1]

    def predict_proba_ensemble(self, X: np.ndarray, w_rf: float = 0.5, w_xgb: float = 0.5) -> np.ndarray:
        p_rf = self.predict_proba_rf(X)
        p_xgb = self.predict_proba_xgb(X)
        return w_rf * p_rf + w_xgb * p_xgb
