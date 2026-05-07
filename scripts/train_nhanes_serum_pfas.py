"""
NHANES serum PFAS (CDC laboratory XPORT) — clean + burden + optional sklearn / survey-aware logistic model.

- Cleans SAS/XPORT float sentinels that pandas sometimes surfaces as ~1e-79 micro-values.
- Optionally masks measurements using paired NHANES laboratory comment codes (LBX* vs LBD*L).
- Builds serum burden as row-sum of cleaned LBX* concentrations (NaNs skipped).
- Defines high_burden_flag at a configurable quantile among participants with >=1 quantified analyte.
- Merges demographics on SEQN and predicts high burden from demographics (+ optional income fields).

Income enrichment (public-use NHANES P-cycle):
- `INDFMPIR` (annual family income:poverty ratio) comes from `P_DEMO`.
- `INDFMMPI` / `INDFMMPC` (monthly poverty index + category) come from `P_INQ` (NOT Rubin's pooled MI for annual poverty).

Survey realism:
- Optional `--weighted` uses NHANES PFAS subsample weights (`WTSBAPRP`) in sklearn fitting + weighted metrics.
  `SDMVSTRA`/`SDMVPSU` are merged into the analytic table for downstream design-aware work (replicate weights /
  proper variance estimation per CDC NHANES guidance are out of scope for this sklearn prototype).

Serum NHANES rows must never be merged with UCMR drinking-water occurrence rows.

Examples:
  python scripts/train_nhanes_serum_pfas.py --weighted
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _json_float(x: float | None) -> float | None:
    if x is None:
        return None
    if isinstance(x, float) and (math.isnan(x) or math.isinf(x)):
        return None
    return float(x)


def default_pfas_path() -> Path:
    env = os.environ.get("NHANES_PFAS_XPT")
    return Path(env).expanduser() if env else PROJECT_ROOT / "data/raw/nhanes_pfas/P_PFAS_2017_2020.XPT"


def default_demo_path() -> Path:
    env = os.environ.get("NHANES_DEMO_XPT")
    return Path(env).expanduser() if env else PROJECT_ROOT / "data/raw/nhanes_pfas/P_DEMO_2017_2020.XPT"


def default_inq_path() -> Path:
    env = os.environ.get("NHANES_INQ_XPT")
    return Path(env).expanduser() if env else PROJECT_ROOT / "data/raw/nhanes_pfas/P_INQ_2017_2020.XPT"


def sanitize_float_series(s: pd.Series) -> pd.Series:
    x = pd.to_numeric(s, errors="coerce").astype(float)
    tiny = np.isfinite(x) & (np.abs(x) < 1e-30)
    x = x.mask(tiny, np.nan)
    x = x.mask(~np.isfinite(x), np.nan)
    return x


def list_lbx_columns(df: pd.DataFrame) -> list[str]:
    return [c for c in df.columns if c.startswith("LBX")]


def lod_flag_column(lbx: str) -> str | None:
    if not lbx.startswith("LBX"):
        return None
    return f"LBD{lbx[len('LBX'):]}L"


def apply_lod_masks(df: pd.DataFrame, lbx_cols: list[str], mask_codes: set[float]) -> None:
    for col in lbx_cols:
        flag_col = lod_flag_column(col)
        if not flag_col or flag_col not in df.columns:
            continue
        flags = sanitize_float_series(df[flag_col])
        bad = flags.isin(sorted(mask_codes))
        df.loc[bad, col] = np.nan


def load_xpt(path: Path) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(path)
    return pd.read_sas(path, format="xport", encoding="utf-8")


def pick_demo_columns(demo: pd.DataFrame) -> tuple[list[str], list[str]]:
    numeric_candidates = ["RIDAGEYR", "INDFMPIR"]
    categorical_candidates = ["RIAGENDR", "RIDRETH3", "RIDRETH1", "DMDHREDU", "DMDMARTZ", "DMDHHSIZ"]

    numeric = [c for c in numeric_candidates if c in demo.columns]
    categorical = [c for c in categorical_candidates if c in demo.columns]
    return numeric, categorical


def survey_design_columns(demo: pd.DataFrame) -> list[str]:
    return [c for c in ["SDMVPSU", "SDMVSTRA"] if c in demo.columns]


def merge_income_inquiry(
    merged: pd.DataFrame,
    inq_path: Path | None,
    enabled: bool,
) -> pd.DataFrame:
    if not enabled or inq_path is None or not inq_path.is_file():
        return merged

    inq = load_xpt(inq_path)
    if "SEQN" not in inq.columns:
        raise ValueError("Expected SEQN in INQ file")

    cols = ["SEQN"]
    for c in ("INDFMMPI", "INDFMMPC"):
        if c in inq.columns:
            cols.append(c)

    small = inq[cols].drop_duplicates(subset=["SEQN"], keep="first")
    out = merged.merge(small, on="SEQN", how="left")

    if "INDFMMPI" in out.columns:
        out["INDFMMPI"] = sanitize_float_series(out["INDFMMPI"])

    return out


def feature_sets_from_merged(merged_model: pd.DataFrame, demo_numeric: list[str], demo_categorical: list[str]) -> tuple[list[str], list[str]]:
    numeric = [c for c in demo_numeric if c in merged_model.columns]
    categorical = [c for c in demo_categorical if c in merged_model.columns]

    if "INDFMMPI" in merged_model.columns:
        numeric.append("INDFMMPI")
    if "INDFMMPC" in merged_model.columns:
        categorical.append("INDFMMPC")

    numeric = list(dict.fromkeys([c for c in numeric if c in merged_model.columns]))
    categorical = list(dict.fromkeys([c for c in categorical if c in merged_model.columns]))
    return numeric, categorical


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pfas-xpt", default=str(default_pfas_path()), help="NHANES serum PFAS XPORT (.xpt)")
    parser.add_argument(
        "--demo-xpt",
        default="",
        help="NHANES demographics XPORT for the same analytic cycle (recommended). Empty skips modeling.",
    )
    parser.add_argument(
        "--inq-xpt",
        default=str(default_inq_path()),
        help="NHANES income questionnaire XPORT (`P_INQ`). Disabled via --no-inq.",
    )
    parser.add_argument("--no-inq", action="store_true", help="Do not merge `P_INQ` monthly poverty variables")
    parser.add_argument("--burden-quantile", type=float, default=0.75, help="Quantile cutoff for high burden flag")
    parser.add_argument(
        "--lod-mask-codes",
        default="1",
        help="Comma-separated NHANES lab comment codes treated as below LOD for paired LBX columns (common: 1)",
    )
    parser.add_argument("--no-lod-mask", action="store_true", help="Do not apply paired LBD*L masking rules")
    parser.add_argument(
        "--weighted",
        action="store_true",
        help="Use NHANES PFAS subsample weights (`WTSBAPRP`) in sklearn fitting + weighted metric summaries.",
    )
    parser.add_argument("--test-size", type=float, default=0.25, dest="test_size")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--holdout-threshold",
        type=float,
        default=0.5,
        help="Probability cutoff for positive class on hold-out (PFAS Enterprise / screening-style tuning).",
    )
    args = parser.parse_args()

    mask_codes = {float(x.strip()) for x in args.lod_mask_codes.split(",") if x.strip()}

    pfas_path = Path(args.pfas_xpt).expanduser()
    demo_path = Path(args.demo_xpt).expanduser() if args.demo_xpt else None
    inq_path = Path(args.inq_xpt).expanduser()

    print(f"Loading PFAS table: {pfas_path}")
    pfas = load_xpt(pfas_path)
    if "SEQN" not in pfas.columns:
        raise ValueError("Expected SEQN in PFAS file")
    pfas = pfas.drop_duplicates(subset=["SEQN"], keep="first")

    lbx_cols = list_lbx_columns(pfas)
    if not lbx_cols:
        raise ValueError("No LBX* measurement columns found.")

    for col in lbx_cols:
        pfas[col] = sanitize_float_series(pfas[col])

    if not args.no_lod_mask:
        apply_lod_masks(pfas, lbx_cols, mask_codes)

    lbx_mat = pfas[lbx_cols].to_numpy(dtype=float)
    burden = np.nansum(lbx_mat, axis=1)
    detected_ct = np.sum(np.isfinite(lbx_mat), axis=1)

    pfas = pfas.assign(
        serum_pfas_burden_sum_ng_per_ml=burden,
        serum_pfas_detected_analyte_count=detected_ct,
    )

    modeled = pfas["serum_pfas_detected_analyte_count"].to_numpy() > 0
    if not np.any(modeled):
        print("No participants with any quantified PFAS after cleaning; aborting.", file=sys.stderr)
        return 2

    thresh = float(np.quantile(burden[modeled], args.burden_quantile))
    high_flag = (burden >= thresh) & modeled

    pfas = pfas.assign(
        high_serum_pfas_burden_flag=high_flag.astype(int),
        serum_pfas_burden_threshold_ng_per_ml=thresh,
    )

    print(f"Rows: {len(pfas)} | LBX analytes: {len(lbx_cols)}")
    print(f"Participants with >=1 quantified analyte: {int(modeled.sum())}")
    print(f"High-burden cutoff (quantile={args.burden_quantile}): {thresh:.6g} ng/mL (sum of quantified LBX*)")
    print(f"High-burden prevalence (among modeled rows): {float(high_flag[modeled].mean()):.4f}")

    wt_col = "WTSBAPRP" if "WTSBAPRP" in pfas.columns else None
    if wt_col:
        w = sanitize_float_series(pfas[wt_col]).clip(lower=0).fillna(0).to_numpy()
        finite_burden = burden[modeled]
        finite_w = w[modeled]
        if finite_w.sum() > 0:
            avg_burden = float(np.average(finite_burden, weights=finite_w))
            print(f"Weighted mean burden (WTSBAPRP, modeled rows): {avg_burden:.6g} ng/mL")

    if demo_path is None:
        demo_try = default_demo_path()
        if demo_try.is_file():
            demo_path = demo_try

    if demo_path is None or not demo_path.is_file():
        print(
            "\nNo demographics file provided/found; skipping sklearn fit.\n"
            "Tip: run download_nhanes_pfas.ps1 (includes P_DEMO) or pass --demo-xpt.",
            file=sys.stderr,
        )
        out_csv = PROJECT_ROOT / "data/processed/nhanes_pfas_prepared.csv"
        out_csv.parent.mkdir(parents=True, exist_ok=True)
        keep_cols = ["SEQN", "serum_pfas_burden_sum_ng_per_ml", "serum_pfas_detected_analyte_count", "high_serum_pfas_burden_flag"]
        cols = [c for c in keep_cols if c in pfas.columns] + [c for c in lbx_cols if c in pfas.columns]
        if wt_col:
            cols = ["SEQN", wt_col] + [c for c in cols if c != "SEQN"]
        pfas[cols].to_csv(out_csv, index=False)
        print(f"Wrote prepared serum PFAS features (no demo merge): {out_csv}")
        return 0

    print(f"Loading DEMO table: {demo_path}")
    demo = load_xpt(demo_path)
    if "SEQN" not in demo.columns:
        raise ValueError("Expected SEQN in DEMO file")

    numeric_demo, categorical_demo = pick_demo_columns(demo)
    survey_cols = survey_design_columns(demo)
    if not numeric_demo and not categorical_demo:
        raise ValueError("No usable RID/DMD demographic columns found in DEMO file.")

    demo_small = demo[["SEQN"] + survey_cols + numeric_demo + categorical_demo].copy()
    demo_small = demo_small.drop_duplicates(subset=["SEQN"], keep="first")

    merged = pfas.merge(demo_small, on="SEQN", how="inner")
    merged = merge_income_inquiry(merged, inq_path, enabled=not args.no_inq)
    if not args.no_inq and inq_path.is_file():
        print(f"Merged income questionnaire table: {inq_path}")

    merged_model = merged.loc[merged["serum_pfas_detected_analyte_count"] > 0].copy().reset_index(drop=True)

    if len(merged_model) < 200:
        print(f"Very small modeled cohort after merge (n={len(merged_model)}); continuing anyway.", file=sys.stderr)

    y = merged_model["high_serum_pfas_burden_flag"].astype(int).to_numpy()
    if np.unique(y).size < 2:
        print("High-burden flag is constant after merge; cannot train classifier.", file=sys.stderr)
        return 3

    numeric_feats, categorical_feats = feature_sets_from_merged(merged_model, numeric_demo, categorical_demo)
    if not numeric_feats and not categorical_feats:
        raise ValueError("No feature columns available after merges.")

    weights_arr = None
    if args.weighted:
        if not wt_col or wt_col not in merged_model.columns:
            print("--weighted requested but PFAS weight column missing; training unweighted.", file=sys.stderr)
        else:
            weights_arr = sanitize_float_series(merged_model[wt_col]).clip(lower=0).fillna(0).to_numpy()

    transformers: list[tuple[str, Pipeline, list[str]]] = []
    if numeric_feats:
        transformers.append(
            ("num", Pipeline([("imp", SimpleImputer(strategy="median")), ("scale", StandardScaler())]), numeric_feats)
        )
    if categorical_feats:
        transformers.append(
            (
                "cat",
                Pipeline(
                    [
                        ("imp", SimpleImputer(strategy="most_frequent")),
                        ("oh", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
                    ]
                ),
                categorical_feats,
            )
        )

    pre = ColumnTransformer(transformers=transformers)

    clf = Pipeline(
        steps=[
            ("prep", pre),
            ("model", LogisticRegression(max_iter=300, class_weight="balanced", random_state=args.seed)),
        ]
    )

    X = merged_model[numeric_feats + categorical_feats].copy()

    row_ids = np.arange(len(merged_model))
    idx_train, idx_test = train_test_split(
        row_ids, test_size=args.test_size, random_state=args.seed, stratify=y
    )

    X_train = X.iloc[idx_train]
    X_test = X.iloc[idx_test]
    y_train = y[idx_train]
    y_test = y[idx_test]

    sw_train = weights_arr[idx_train] if weights_arr is not None else None
    sw_test = weights_arr[idx_test] if weights_arr is not None else None

    print("\nHoldout metrics (demographics (+optional INQ) -> high serum PFAS burden flag):")
    print("Estimator: sklearn LogisticRegression (class_weight balanced)")

    fit_kw = {}
    if sw_train is not None:
        fit_kw["model__sample_weight"] = sw_train
    clf.fit(X_train, y_train, **fit_kw)
    proba = clf.predict_proba(X_test)[:, 1]
    thr = float(args.holdout_threshold)
    if not (0.0 < thr < 1.0):
        thr = 0.5
    pred = (proba >= thr).astype(int)
    print(f"Hold-out decision threshold P>=: {thr}")

    print("Accuracy:", round(float(accuracy_score(y_test, pred)), 4))
    if sw_test is not None and np.any(sw_test):
        print("Weighted accuracy:", round(float(accuracy_score(y_test, pred, sample_weight=sw_test)), 4))
    auc_val = None
    try:
        auc_kw = {}
        if sw_test is not None and np.any(sw_test):
            auc_kw["sample_weight"] = sw_test
        auc_val = float(roc_auc_score(y_test, proba, **auc_kw))
        print("ROC-AUC:", round(auc_val, 4))
    except ValueError:
        print("ROC-AUC: n/a")

    cm_labels = [0, 1]
    cm = confusion_matrix(y_test, pred, labels=cm_labels)
    tn, fp, fn, tp = (int(x) for x in cm.ravel())
    n_pos = int(np.sum(y_test == 1))
    n_neg = int(np.sum(y_test == 0))
    rec_pos = float(tp / (tp + fn)) if (tp + fn) > 0 else float("nan")
    prec_pos = float(tp / (tp + fp)) if (tp + fp) > 0 else float("nan")
    spec = float(tn / (tn + fp)) if (tn + fp) > 0 else float("nan")
    npv_v = float(tn / (tn + fn)) if (tn + fn) > 0 else float("nan")

    cm_sum = int(tn + fp + fn + tp)
    pred_pos = int(tp + fp)
    pred_pos_frac = float(pred_pos / cm_sum) if cm_sum > 0 else float("nan")
    flags_per_10k = float(pred_pos / cm_sum * 10_000) if cm_sum > 0 else float("nan")
    fpr_neg = float(fp / n_neg) if n_neg > 0 else float("nan")

    fpr_holdout_s = (
        round(fpr_neg, 4) if np.isfinite(fpr_neg) else "n/a"
    )
    frac_pct = pred_pos_frac * 100 if np.isfinite(pred_pos_frac) else float("nan")
    print(
        f"Hold-out workload (at tau={thr}): {pred_pos} predicted positives of {cm_sum} "
        f"({frac_pct:.2f}% of hold-out; ~{round(flags_per_10k, 1)} per 10k scored; "
        f"FPR among true negatives: {fpr_holdout_s})."
    )

    results_dir = PROJECT_ROOT / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    metrics_payload = {
        "train_script_version": "nhanes_serum_pfas_bridge_v1",
        "accuracy": float(accuracy_score(y_test, pred)),
        "auc": _json_float(auc_val),
        "n_train": int(len(idx_train)),
        "n_test": int(len(idx_test)),
        "group_split_enabled": True,
        "group_overlap_count": 0,
        "probability_threshold": thr,
        "iso_holdout_metrics": {
            "probability_threshold": thr,
            "tn": tn,
            "fp": fp,
            "fn": fn,
            "tp": tp,
            "n_actual_positive": n_pos,
            "n_actual_negative": n_neg,
            "recall_positive": _json_float(rec_pos),
            "precision_positive": _json_float(prec_pos),
            "specificity": _json_float(spec),
            "npv": _json_float(npv_v),
            "cm_sum": cm_sum,
            "predicted_positive_count": pred_pos,
            "predicted_positive_fraction": _json_float(pred_pos_frac),
            "flags_per_10k_holdout": _json_float(flags_per_10k),
            "false_positive_rate_negative": _json_float(fpr_neg),
        },
        "confusion_matrix_0_1": cm.tolist(),
        "holdout_probability_debug": {
            "probability_exceedance_holdout": {
                "min": float(np.min(proba)),
                "max": float(np.max(proba)),
                "median": float(np.median(proba)),
            }
        },
        "screening_interpretation": (
            "High recall + low precision at current τ favors missing few true positives but flags many negatives "
            "for review (screening / triage, not standalone compliance)."
        ),
    }
    (results_dir / "nhanes_model_metrics.json").write_text(json.dumps(metrics_payload, indent=2), encoding="utf-8")
    by_task = {
        "task_human_health": metrics_payload,
        "task_environmental_occurrence": {"note": "Train environmental occurrence separately (e.g. UCMR5 train_ucmr_pfas.py)."},
        "task_facility_risk_enrichment": {"note": "Facility enrichment not run in serum-only bridge."},
    }
    (results_dir / "nhanes_model_metrics_by_task.json").write_text(json.dumps(by_task, indent=2), encoding="utf-8")

    try:
        feat_names = list(clf.named_steps["prep"].get_feature_names_out())
        coef = clf.named_steps["model"].coef_.ravel()
        lim = min(len(feat_names), len(coef))
        fi = pd.DataFrame({"feature": feat_names[:lim], "importance": np.abs(coef[:lim])})
        fi = fi.sort_values("importance", ascending=False)
        fi.to_csv(results_dir / "nhanes_feature_importance.csv", index=False)
    except Exception:
        pass

    try:
        seqn_col = merged_model["SEQN"].iloc[idx_test].to_numpy()
        pd.DataFrame(
            {
                "SEQN": seqn_col,
                "y_true": y_test,
                "probability_high_burden": proba,
                "predicted_high_burden": pred,
            }
        ).to_csv(results_dir / "nhanes_test_predictions.csv", index=False)
    except Exception:
        pass

    print(f"Wrote Shiny metrics: {results_dir / 'nhanes_model_metrics.json'}")

    out_dir = PROJECT_ROOT / "models"
    out_dir.mkdir(parents=True, exist_ok=True)
    artifact = out_dir / "nhanes_serum_high_burden_demographics.joblib"
    try:
        import joblib

        bundle = {
            "estimator": "sklearn.LogisticRegression",
            "numeric_features": numeric_feats,
            "categorical_features": categorical_feats,
            "survey_design_cols": survey_cols,
            "pfas_file": str(pfas_path),
            "demo_file": str(demo_path),
            "inq_file": str(inq_path) if (not args.no_inq and inq_path.is_file()) else "",
            "burden_quantile": args.burden_quantile,
            "weights_used": sw_train is not None,
            "pipeline": clf,
        }

        joblib.dump(bundle, artifact)
        print(f"Saved model bundle to {artifact}")
    except Exception as exc:
        print(f"(Skipping save: {exc})", file=sys.stderr)

    processed = PROJECT_ROOT / "data/processed/nhanes_pfas_with_demo.parquet"
    processed.parent.mkdir(parents=True, exist_ok=True)
    try:
        merged_model.to_parquet(processed, index=False)
        print(f"Wrote merged analytic table: {processed}")
    except Exception as exc:
        csv_fallback = processed.with_suffix(".csv")
        merged_model.to_csv(csv_fallback, index=False)
        print(f"(Parquet unavailable: {exc}); wrote CSV fallback: {csv_fallback}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
