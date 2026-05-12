"""
Train a small sklearn model on UCMR-style PFAS rows.

- Default task: classify detected (=) vs non-detect (<) from AnalyticalResultsSign.
- Uses env UCMR_DATA_PATH or --path to a tab-separated EPA text file.
- Writes model bundle plus threshold sweep, training metrics, and provenance under models/.

Example (PowerShell):
  $env:UCMR_DATA_PATH = 'C:\\path\\UCMR5_533.txt'
  python scripts/train_ucmr_pfas.py --max-rows 200000

If you pass --path, it must exist; otherwise the script exits with an error (no silent fallback to synthetic).
Omit --path and UCMR_DATA_PATH only when you intentionally want the small built-in synthetic dataset.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

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


def build_threshold_sweep_table(y_true: np.ndarray, proba: np.ndarray, thresholds: np.ndarray) -> pd.DataFrame:
    """One row per threshold; positive class = detect (=)."""
    n = int(len(y_true))
    rows: list[dict[str, float | int]] = []
    for t in thresholds:
        pred = (proba >= float(t)).astype(int)
        tp = int(np.sum((pred == 1) & (y_true == 1)))
        fp = int(np.sum((pred == 1) & (y_true == 0)))
        fn = int(np.sum((pred == 0) & (y_true == 1)))
        prec = float(tp / (tp + fp)) if (tp + fp) else 0.0
        rec = float(tp / (tp + fn)) if (tp + fn) else 0.0
        f1 = float(2 * prec * rec / (prec + rec)) if (prec + rec) else 0.0
        ppr = float((tp + fp) / n) if n else 0.0
        flags_per_10k = float(ppr * 10_000)
        fp_per_tp = float(fp / tp) if tp > 0 else float("nan")
        rows.append(
            {
                "threshold": float(t),
                "precision_detect": prec,
                "recall_detect": rec,
                "f1_detect": f1,
                "predicted_positive_rate": ppr,
                "flags_per_10k": flags_per_10k,
                "false_positives": fp,
                "true_positives": tp,
                "false_positives_per_true_positive": fp_per_tp,
            }
        )
    return pd.DataFrame(rows)


def pick_best_high_recall_screening_row(sweep: pd.DataFrame, recall_floor: float = 0.95) -> pd.Series:
    """
    Prefer thresholds with recall_detect >= recall_floor and true_positives > 0;
    minimize false_positives_per_true_positive (tie-break: higher threshold).
    If none meet the floor, restrict to max recall among TP>0 rows, then same rule.
    """
    work = sweep.copy()
    valid = work["true_positives"] > 0
    if not valid.any():
        return work.iloc[int(work["recall_detect"].values.argmax())]
    high = work.loc[valid & (work["recall_detect"] >= recall_floor)]
    pool = high if len(high) else work.loc[valid & (work["recall_detect"] >= work.loc[valid, "recall_detect"].max() - 1e-15)]
    return pool.sort_values(
        by=["false_positives_per_true_positive", "threshold"],
        ascending=[True, False],
        na_position="last",
    ).iloc[0]


def round_for_json(obj: Any, ndigits: int) -> Any:
    """Recursively round floats for stable JSON; non-finite floats become null."""
    if isinstance(obj, dict):
        return {k: round_for_json(v, ndigits) for k, v in obj.items()}
    if isinstance(obj, list):
        return [round_for_json(v, ndigits) for v in obj]
    if isinstance(obj, bool):
        return obj
    if isinstance(obj, (np.integer, int)):
        return int(obj)
    if isinstance(obj, (np.floating, float)):
        x = float(obj)
        if not np.isfinite(x):
            return None
        return round(x, ndigits)
    return obj


def dumps_json_rounded(data: Any, ndigits: int) -> str:
    return json.dumps(round_for_json(data, ndigits), indent=2, allow_nan=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", default=os.environ.get("UCMR_DATA_PATH", ""), help="Tab-separated UCMR file")
    parser.add_argument("--max-rows", type=int, default=None, help="Optional row cap when reading CSV")
    parser.add_argument("--encoding", default="latin-1", help="File encoding (EPA texts often need latin-1)")
    parser.add_argument("--test-size", type=float, default=0.25, dest="test_size")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--recall-floor",
        type=float,
        default=0.95,
        dest="recall_floor",
        help="Minimum recall_detect when choosing the reported high-recall screening threshold (default: 0.95)",
    )
    parser.add_argument(
        "--json-float-digits",
        type=int,
        default=6,
        dest="json_float_digits",
        help="Decimal places for floats written to JSON artifacts (default: 6)",
    )
    args = parser.parse_args()

    if not (0.0 < args.recall_floor <= 1.0):
        print("ERROR: --recall-floor must be in (0, 1].", file=sys.stderr)
        return 4
    if args.json_float_digits < 0 or args.json_float_digits > 16:
        print("ERROR: --json-float-digits must be between 0 and 16.", file=sys.stderr)
        return 4

    path = Path(args.path).expanduser() if args.path else None
    if path and path.is_file():
        print(f"Loading {path} ...")
        df = load_ucmr_frame(path, args.max_rows, args.encoding)
    else:
        if args.path:
            print(
                f"ERROR: --path not found or not a file: {path}. "
                "Fix the path (e.g. EPA UCMR5_533.txt). Omit --path only to use built-in synthetic data.",
                file=sys.stderr,
            )
            return 3
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
    pred_default = (proba >= 0.5).astype(int)
    acc = float(accuracy_score(y_test, pred_default))
    print("Accuracy:", round(acc, 4))
    try:
        roc = float(roc_auc_score(y_test, proba))
        print("ROC-AUC:", round(roc, 4))
    except ValueError:
        roc = None
        print("ROC-AUC: n/a")
    print(classification_report(y_test, pred_default, target_names=["non-detect (<)", "detect (=)"], digits=3))

    out_dir = Path(__file__).resolve().parents[1] / "models"
    out_dir.mkdir(parents=True, exist_ok=True)
    artifact = out_dir / "pfas_detect_sklearn.joblib"
    sweep_path = out_dir / "ucmr_threshold_sweep.csv"
    metrics_path = out_dir / "ucmr_training_metrics.json"
    provenance_path = out_dir / "ucmr_training_provenance.json"

    thresholds = np.linspace(0.0, 1.0, 1001)
    sweep = build_threshold_sweep_table(y_test, proba, thresholds)
    sweep.to_csv(sweep_path, index=False)

    best_row = pick_best_high_recall_screening_row(sweep, recall_floor=args.recall_floor)
    fp_per_tp = best_row["false_positives_per_true_positive"]
    fp_per_tp_out = None if pd.isna(fp_per_tp) else float(fp_per_tp)

    print()
    print(f"Best high-recall screening threshold (recall_floor={args.recall_floor:g}):")
    print(f"threshold={best_row['threshold']:.6f}")
    print(f"recall_detect={best_row['recall_detect']:.4f}")
    print(f"precision_detect={best_row['precision_detect']:.4f}")
    print(f"flags_per_10k={best_row['flags_per_10k']:.2f}")
    if fp_per_tp_out is None:
        print("FP per TP=n/a")
    else:
        print(f"FP per TP={fp_per_tp_out:.4f}")

    created_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    resolved_source = path.resolve().as_posix() if path and path.is_file() else None
    provenance = {
        "source_path": resolved_source if resolved_source else "synthetic",
        "source_file": path.name if path and path.is_file() else "builtin",
        "row_cap": int(args.max_rows) if args.max_rows is not None else None,
        "encoding": args.encoding,
        "test_size": float(args.test_size),
        "seed": int(args.seed),
        "n_rows_used": int(len(X)),
        "n_train": int(len(X_train)),
        "n_test": int(len(X_test)),
        "positive_class": "=",
        "model_file": artifact.name,
        "recall_floor": float(args.recall_floor),
        "json_float_digits": int(args.json_float_digits),
        "created_at": created_at,
    }
    provenance_path.write_text(dumps_json_rounded(provenance, args.json_float_digits), encoding="utf-8")

    metrics = {
        "accuracy_default_threshold_0_5": acc,
        "roc_auc": roc,
        "recall_floor": float(args.recall_floor),
        "classification_report_default_0_5": classification_report(
            y_test, pred_default, target_names=["non-detect (<)", "detect (=)"], output_dict=True, zero_division=0
        ),
        "best_high_recall_screening_threshold": {
            "threshold": float(best_row["threshold"]),
            "recall_detect": float(best_row["recall_detect"]),
            "precision_detect": float(best_row["precision_detect"]),
            "f1_detect": float(best_row["f1_detect"]),
            "flags_per_10k": float(best_row["flags_per_10k"]),
            "false_positives_per_true_positive": fp_per_tp_out,
            "true_positives": int(best_row["true_positives"]),
            "false_positives": int(best_row["false_positives"]),
        },
        "threshold_sweep_file": sweep_path.name,
        "provenance_file": provenance_path.name,
    }
    metrics_path.write_text(dumps_json_rounded(metrics, args.json_float_digits), encoding="utf-8")

    try:
        import joblib

        joblib.dump({"pipeline": clf, "features": numeric + categorical}, artifact)
        print(f"Saved model bundle to {artifact}")
        print(f"Wrote threshold sweep to {sweep_path}")
        print(f"Wrote training metrics to {metrics_path}")
        print(f"Wrote provenance to {provenance_path}")
    except Exception as exc:
        print(f"(Skipping save: {exc})", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
