"""Train and evaluate a placement outcome classifier."""
from pathlib import Path
import json
import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    accuracy_score, classification_report, confusion_matrix,
    f1_score, precision_score, recall_score, roc_auc_score
)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "raw" / "campus_placement.csv"
MODELS = ROOT / "models"
REPORTS = ROOT / "reports"
MODELS.mkdir(exist_ok=True)
REPORTS.mkdir(exist_ok=True)


def encode_target(values: pd.Series) -> pd.Series:
    normalized = values.astype(str).str.strip().str.lower().str.replace("_", "", regex=False)
    mapping = {
        "placed": 1, "yes": 1, "1": 1, "true": 1,
        "notplaced": 0, "not placed": 0, "no": 0, "0": 0, "false": 0,
    }
    target = normalized.map(mapping)
    if target.isna().any():
        unknown = sorted(normalized[target.isna()].unique().tolist())
        raise ValueError(f"Unrecognized PlacementStatus values: {unknown}")
    return target.astype(int)


def main() -> None:
    if not DATA.exists():
        raise FileNotFoundError("Run python data/download_data.py first.")
    df = pd.read_csv(DATA)
    if "PlacementStatus" not in df:
        raise ValueError("Expected PlacementStatus target column.")
    y = encode_target(df.pop("PlacementStatus"))
    # The publisher's train/validation/test split is preferred. Validation rows
    # are included in fitting; the official test split remains untouched.
    split_labels = df["SourceSplit"].astype(str).str.lower() if "SourceSplit" in df else None
    if split_labels is not None and {"train", "test"}.issubset(set(split_labels.dropna())):
        train_mask = split_labels.isin(["train", "validation", "valid"])
        test_mask = split_labels.eq("test")
        if not train_mask.any() or not test_mask.any():
            raise ValueError("SourceSplit metadata found, but train/test rows are incomplete.")
        X = df.drop(columns=["SourceSplit"], errors="ignore")
        split_method = "official train + validation; official test"
    else:
        X = df.drop(columns=["SourceSplit"], errors="ignore")
        train_mask = None
        test_mask = None
        split_method = "stratified random 80/20 fallback"

    # Remove unusable/identifier columns before splitting, keeping train/test
    # feature columns exactly aligned.
    X = X.dropna(axis=1, how="all")
    id_like = [c for c in X if c.lower() in {"id", "studentid", "student_id", "row_id"}]
    X = X.drop(columns=id_like, errors="ignore")
    if X.empty:
        raise ValueError("No usable predictor columns remain.")

    if train_mask is not None and test_mask is not None:
        X_train, X_test = X.loc[train_mask], X.loc[test_mask]
        y_train, y_test = y.loc[train_mask], y.loc[test_mask]
    else:
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, stratify=y, random_state=42
        )

    categorical = X.select_dtypes(include=["object", "bool", "category"]).columns.tolist()
    numeric = [c for c in X.columns if c not in categorical]
    transformers = []
    if numeric:
        transformers.append(("numeric", SimpleImputer(strategy="median"), numeric))
    if categorical:
        transformers.append(("categorical", Pipeline([
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("onehot", OneHotEncoder(handle_unknown="ignore")),
        ]), categorical))
    preprocessor = ColumnTransformer(transformers, remainder="drop")
    classifier = RandomForestClassifier(
        n_estimators=400, min_samples_leaf=2,
        class_weight="balanced_subsample", random_state=42, n_jobs=-1
    )
    pipeline = Pipeline([("preprocess", preprocessor), ("model", classifier)])
    pipeline.fit(X_train, y_train)
    probabilities = pipeline.predict_proba(X_test)[:, 1]
    predictions = (probabilities >= 0.5).astype(int)
    metrics = {
        "rows": int(len(df)),
        "placed_rate": float(y.mean()),
        "accuracy": float(accuracy_score(y_test, predictions)),
        "precision": float(precision_score(y_test, predictions, zero_division=0)),
        "recall": float(recall_score(y_test, predictions, zero_division=0)),
        "f1": float(f1_score(y_test, predictions, zero_division=0)),
        "roc_auc": float(roc_auc_score(y_test, probabilities)),
        "confusion_matrix": confusion_matrix(y_test, predictions).tolist(),
        "classification_report": classification_report(
            y_test, predictions, output_dict=True, zero_division=0
        ),
        "threshold": 0.5,
        "split_method": split_method,
        "train_rows": int(len(X_train)),
        "test_rows": int(len(X_test)),
        "predictor_columns": X.columns.tolist(),
    }
    joblib.dump(pipeline, MODELS / "placement_pipeline.joblib")
    (REPORTS / "placement_metrics.json").write_text(json.dumps(metrics, indent=2))

    names = pipeline.named_steps["preprocess"].get_feature_names_out()
    importances = pipeline.named_steps["model"].feature_importances_
    pd.DataFrame({"feature": names, "importance": importances}).sort_values(
        "importance", ascending=False
    ).to_csv(REPORTS / "feature_importance.csv", index=False)
    print(json.dumps({k: v for k, v in metrics.items() if k != "classification_report"}, indent=2))


if __name__ == "__main__":
    main()
