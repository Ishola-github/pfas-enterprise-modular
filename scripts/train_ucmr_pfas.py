"""
Train a small sklearn model on UCMR-style PFAS rows.

- Default task: classify detected (=) vs non-detect (<) from AnalyticalResultsSign.
- Uses env UCMR_DATA_PATH or --path to a tab-separated EPA text file.
- If the file is missing, trains on synthetic data so the pipeline stays testable.

Example (PowerShell):
  $env:UCMR_DATA_PATH = 'C:\\path\\UCMR5_533.txt'
  python scripts/train_ucmr_pfas.py --max-rows 200000
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


def build_synthetic(n: int = 5000, seed: int = 42) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    contaminants = np.array(["HFPO-DA", "PFBS", "PFBA", "PFOA", "PFOS"])
    mrl_by_chem = {"HFPO-DA": 0.005, "PFBS": 0.003, "PFBA": 0.005, "PFOA": 0.004, "PFOS": 0.004}
    chem_idx_map = {name: float(i) for i, name in enumerate(contaminants)}
    chem = rng.choice(contaminants, size=n)
    mrl = np.array([mrl_by_chem[c] for c in chem])
    chem_idx = np.array([chem_idx_map[c] for c in chem])
    noise = rng.normal(0, 1, size=n)
    logit = -1.0 + 0.55 * (mrl * 1000.0) + 0.18 * chem_idx + 0.45 * noise
    detect_prob = 1 / (1 + np.exp(-logit))
    is_detect = rng.random(n) < detect_prob
    sign = np.where(is_detect, "=", "<")
    value = np.where(is_detect, mrl * rng.uniform(1.0, 8.0, size=n), np.nan)
    return pd.DataFrame(
        {
            "Contaminant": chem,
            "MRL": mrl,
            "Units": "µg/L",
            "AnalyticalResultsSign": sign,
            "AnalyticalResultValue": value,
            "Region": rng.choice(["1", "2", "3", "4", "5"], size=n),
            "Size": rng.choice(["S", "L"], size=n),
        }
    )


def load_ucmr_frame(path: Path, max_rows: int | None, encoding: str) -> pd.DataFrame:
    read_kw = dict(sep="\t", encoding=encoding, low_memory=False)
    if max_rows is not None:
        read_kw["nrows"] = max_rows
    df = pd.read_csv(path, **read_kw)
    needed = ["Contaminant", "AnalyticalResultsSign", "AnalyticalResultValue", "MRL"]
    missing = [c for c in needed if c not in df.columns]
    if missing:
        raise ValueError(f"Missing columns {missing}; got {list(df.columns)[:30]}...")
    out = df.copy()
    if "Region" not in out.columns:
        out["Region"] = "unknown"
    if "Size" not in out.columns:
        out["Size"] = "unknown"
    return out


def prepare_xy(df: pd.DataFrame) -> tuple[pd.DataFrame, np.ndarray]:
    y_raw = df["AnalyticalResultsSign"].astype(str).str.strip()
    mask = y_raw.isin(["<", "="])
    X = df.loc[mask, ["Contaminant", "MRL", "AnalyticalResultValue", "Region", "Size"]].copy()
    y = (y_raw[mask] == "=").astype(int).to_numpy()
    return X, y


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", default=os.environ.get("UCMR_DATA_PATH", ""), help="Tab-separated UCMR file")
    parser.add_argument("--max-rows", type=int, default=None, help="Optional row cap when reading CSV")
    parser.add_argument("--encoding", default="latin-1", help="File encoding (EPA texts often need latin-1)")
    parser.add_argument("--test-size", type=float, default=0.25, dest="test_size")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    path = Path(args.path).expanduser() if args.path else None
    if path and path.is_file():
        print(f"Loading {path} ...")
        df = load_ucmr_frame(path, args.max_rows, args.encoding)
    else:
        if args.path:
            print(f"UCMR_DATA_PATH/--path not found ({path}); using synthetic data.", file=sys.stderr)
        df = build_synthetic(n=8000, seed=args.seed)

    X, y = prepare_xy(df)
    if len(np.unique(y)) < 2:
        print("Need both '<' and '=' rows to train a classifier.", file=sys.stderr)
        return 2

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=args.test_size, random_state=args.seed, stratify=y
    )

    numeric = ["MRL", "AnalyticalResultValue"]
    categorical = ["Contaminant", "Region", "Size"]

    pre = ColumnTransformer(
        transformers=[
            ("num", Pipeline([("imp", SimpleImputer(strategy="median")), ("scale", StandardScaler())]), numeric),
            ("cat", Pipeline([("imp", SimpleImputer(strategy="most_frequent")), ("oh", OneHotEncoder(handle_unknown="ignore"))]), categorical),
        ]
    )

    clf = Pipeline([("prep", pre), ("model", LogisticRegression(max_iter=200, class_weight="balanced", random_state=args.seed))])
    clf.fit(X_train, y_train)

    proba = clf.predict_proba(X_test)[:, 1]
    pred = (proba >= 0.5).astype(int)
    print("Accuracy:", round(float(accuracy_score(y_test, pred)), 4))
    try:
        print("ROC-AUC:", round(float(roc_auc_score(y_test, proba)), 4))
    except ValueError:
        print("ROC-AUC: n/a")
    print(classification_report(y_test, pred, target_names=["non-detect (<)", "detect (=)"], digits=3))

    out_dir = Path(__file__).resolve().parents[1] / "models"
    out_dir.mkdir(parents=True, exist_ok=True)
    artifact = out_dir / "pfas_detect_sklearn.joblib"
    try:
        import joblib

        joblib.dump({"pipeline": clf, "features": numeric + categorical}, artifact)
        print(f"Saved model bundle to {artifact}")
    except Exception as exc:
        print(f"(Skipping save: {exc})", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
