import os
import pickle
import pandas as pd
import numpy as np
from lightgbm import LGBMClassifier
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

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "artifacts", "lgbm_procrastination.pkl")

_cached_lgbm_model = None


def train_procrastination(df: pd.DataFrame) -> dict:
    """
    Train LightGBM to predict procrastination risk.
    Label = 1 if task was postponed/skipped/abandoned
    Label = 0 if task was completed
    """
    if len(df) < 10:
        raise ValueError(
            f"Need at least 10 resolved tasks, got {len(df)}."
        )

    # Flip the label — now 1 = procrastinated, 0 = completed
    df["proc_label"] = (df["label"] == 0).astype(int)

    X = df[FEATURES]
    y = df["proc_label"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    model = LGBMClassifier(
        n_estimators   = 200,
        max_depth      = 5,
        learning_rate  = 0.05,
        num_leaves     = 31,
        random_state   = 42,
        verbose        = -1,
    )
    model.fit(
        X_train, y_train,
        eval_set=[(X_test, y_test)],
        callbacks=[],
    )

    y_pred  = model.predict(X_test)
    y_proba = model.predict_proba(X_test)[:, 1]
    auc     = roc_auc_score(y_test, y_proba) if len(set(y_test)) > 1 else 0.0

    # Feature importance
    importance = dict(zip(FEATURES, model.feature_importances_))
    top5 = sorted(importance.items(), key=lambda x: x[1], reverse=True)[:5]

    # Save model
    os.makedirs("ml/artifacts", exist_ok=True)
    with open(MODEL_PATH, "wb") as f:
        pickle.dump(model, f)

    print(classification_report(y_test, y_pred))
    print(f"AUC: {auc:.4f}")
    print(f"Top 5 features: {top5}")

    return {
        "samples_trained" : len(X_train),
        "samples_tested"  : len(X_test),
        "auc"             : round(auc, 4),
        "top_features"    : top5,
    }


def predict_procrastination_risk(task_features: dict) -> float:
    """
    Predict probability that a task will be procrastinated.
    Returns float 0-1. Returns 0.5 if model not trained yet.
    Higher = more likely to procrastinate.
    """
    global _cached_lgbm_model
    if not os.path.exists(MODEL_PATH):
        # Heuristic fallback
        risk  = 0.0
        risk += min(task_features.get("procrastination_count", 0) * 0.15, 0.45)
        risk += min(task_features.get("skip_count", 0) * 0.10, 0.30)
        risk += min(task_features.get("reschedule_count", 0) * 0.05, 0.25)
        return round(min(risk, 1.0), 4)

    if _cached_lgbm_model is None:
        import warnings
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", category=UserWarning)
            with open(MODEL_PATH, "rb") as f:
                _cached_lgbm_model = pickle.load(f)

    model = _cached_lgbm_model

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