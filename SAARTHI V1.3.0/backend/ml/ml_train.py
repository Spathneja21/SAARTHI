import os
import pickle
import numpy as np
import pandas as pd
from xgboost import XGBClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, roc_auc_score


FEATURES = [
    "estimated_duration",
    "priority",
    "category_enc",
    "energy_requirement_enc",
    "procrastination_count",
    "reschedule_count",
    "skip_count",
    "hour_of_day",
    "day_of_week",
]

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "artifacts", "xgb_completion.pkl")

_cached_xgb_model = None


def train(df: pd.DataFrame) -> dict:
    """Train XGBoost on task feature DataFrame."""

    if len(df) < 10:
        raise ValueError(
            f"Not enough data to train — need at least 10 resolved tasks, got {len(df)}."
        )

    X = df[FEATURES]
    y = df["label"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    model = XGBClassifier(
        n_estimators  = 100,
        max_depth      = 4,
        learning_rate  = 0.1,
        use_label_encoder = False,
        eval_metric    = "logloss",
        random_state   = 42,
    )
    model.fit(X_train, y_train)

    y_pred  = model.predict(X_test)
    y_proba = model.predict_proba(X_test)[:, 1]
    auc     = roc_auc_score(y_test, y_proba) if len(set(y_test)) > 1 else 0.0

    # Save model
    os.makedirs("models", exist_ok=True)
    with open(MODEL_PATH, "wb") as f:
        pickle.dump(model, f)

    print(classification_report(y_test, y_pred))
    print(f"AUC: {auc:.4f}")

    return {
        "samples_trained": len(X_train),
        "samples_tested"  : len(X_test),
        "auc"             : round(auc, 4),
    }


def predict_completion(task_features: dict) -> float:
    """
    Predict probability that a task will be completed.
    Returns float 0-1. Returns 0.5 if model not trained yet.
    """
    global _cached_xgb_model
    if not os.path.exists(MODEL_PATH):
        return 0.5

    if _cached_xgb_model is None:
        import warnings
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", category=UserWarning)
            with open(MODEL_PATH, "rb") as f:
                _cached_xgb_model = pickle.load(f)

    model = _cached_xgb_model

    row = pd.DataFrame([{
        "estimated_duration"      : task_features.get("estimated_duration", 60),
        "priority"                : task_features.get("priority", 5),
        "category_enc"            : task_features.get("category_enc", 0),
        "energy_requirement_enc"  : task_features.get("energy_requirement_enc", 2),
        "procrastination_count"   : task_features.get("procrastination_count", 0),
        "reschedule_count"        : task_features.get("reschedule_count", 0),
        "skip_count"              : task_features.get("skip_count", 0),
        "hour_of_day"             : task_features.get("hour_of_day", 9),
        "day_of_week"             : task_features.get("day_of_week", 0),
    }])

    prob = model.predict_proba(row)[0][1]
    return round(float(prob), 4)