#!/usr/bin/env python3
"""
Build a training-ready UCMR exceedance dataset with CAS + DTXSID bridging (CompTox / PFASMASTER-style).

Hybrid use:
  - Run directly:  python scripts/build_ucmr_exceedance_dataset.py --project-root .
  - From R:        Rscript scripts/run_ucmr_dataset_pipeline.R [PROJECT_ROOT]

CLI notes:
  - Aliases: --repo-root (same as --project-root), --bridge (--bridge-csv), --limits (--limits-csv),
    --out (--out-csv).
  - --max-rows-per-file N caps each input file (smoke tests).

Inputs (drop under project data/):
  - UCMR table(s): data/external/epa_ucmr5/ — by default all .csv and .txt (EPA bulk zip uses .txt)
  - Bridge table:  data/external/comptox/pfasmaster_bridge.csv (default search order: comptox, then
    compontox). casrn + dtxsid + optional preferred_name + synonyms when UCMR omits CASRN; see template CSV.
  - Limits table:  data/config/ucmr_analyte_limits_ngl.csv       (CASRN + limit_ng_l)

Output (one merged training table — all UCMR inputs concatenated, labeled):
  - data/training/ucmr_exceedance_labeled.csv
  - data/training/ucmr_exceedance_manifest.json
  Exceedance: PFAS_Risk_Flag == 1 when conc_ng_l >= limit_ng_l (and not nondetect).

Environment overrides:
  PFAS_UCMR_GLOB        single glob e.g. "*.txt" or "UCMR5*.txt" (if unset, uses .csv + .txt)
  PFAS_BRIDGE_CSV       override bridge path
  PFAS_LIMITS_CSV       override limits path
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

# Optional Parquet
try:
    import pyarrow  # noqa: F401

    _HAS_ARROW = True
except Exception:
    _HAS_ARROW = False


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def normalize_cas_key(cas: str | float | None) -> str:
    if cas is None or (isinstance(cas, float) and pd.isna(cas)):
        return ""
    s = re.sub(r"[^0-9]", "", str(cas).strip())
    if not s:
        return ""
    # CAS registry numbers vary in width; compare on digit-only compact form
    return s


def normalize_dtxsid(x: str | float | None) -> str:
    if x is None or (isinstance(x, float) and pd.isna(x)):
        return ""
    s = str(x).strip().upper()
    m = re.search(r"(DTXSID\d+)", s)
    return m.group(1) if m else (s if s.startswith("DTXSID") else "")


def normalize_analyte_key(name: str | float | None) -> str:
    """Lowercase analyte token key: strip noise, unify dashes/punctuation to spaces, collapse whitespace."""
    if name is None or (isinstance(name, float) and pd.isna(name)):
        return ""
    s = str(name).strip()
    if not s or s.lower() in ("nan", "none", "nat"):
        return ""
    s = s.lower().strip()
    # Unicode hyphen / bullet dash variants → space
    s = re.sub(r"[\u2010-\u2015\u2212\ufe58\ufe63\uff0d]+", " ", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def analyte_name_aliases(name: str | float | None) -> list[str]:
    """Tokens used for name↔bridge joins (with-spacing and compact forms when they differ)."""
    k = normalize_analyte_key(name)
    if not k:
        return []
    comp = re.sub(r"\s+", "", k)
    out = [k]
    if comp != k:
        out.append(comp)
    return out


def to_ng_per_l(value: float | None, unit: str | None) -> tuple[float | None, str]:
    """Return (conc_ng_l, note). None conc if cannot parse."""
    note = ""
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None, "missing_value"
    u = "" if unit is None else str(unit).lower().strip()
    u = u.replace("μ", "u").replace("µ", "u")
    v = float(value)
    if u in ("ng/l", "ppt", "ngl"):
        return v, ""
    if u in ("ug/l", "ug/l ", "ppb", "µg/l"):
        return v * 1000.0, ""
    if u in ("mg/l", "ppm"):
        return v * 1_000_000.0, ""
    if u in ("pg/l",):
        return v / 1000.0, ""
    note = f"unknown_unit:{u or 'NA'}"
    return None, note


def detect_column(df: pd.DataFrame, candidates: list[str]) -> str | None:
    cols = {c.lower().strip(): c for c in df.columns}
    for cand in candidates:
        key = cand.lower().strip()
        if key in cols:
            return cols[key]
    # fuzzy: substring match on normalized header
    norm_map = {re.sub(r"[^a-z0-9]+", "", c.lower()): c for c in df.columns}
    for cand in candidates:
        ck = re.sub(r"[^a-z0-9]+", "", cand.lower())
        for nk, orig in norm_map.items():
            if ck in nk or nk in ck:
                return orig
    return None


def load_ucmr(paths: list[Path], max_rows_per_file: int | None = None) -> pd.DataFrame:
    """EPA UCMR 5 occurrence extracts are tab-separated .txt; CSVs use default comma."""
    frames: list[pd.DataFrame] = []
    for p in paths:
        read_kw: dict = {"dtype": str, "low_memory": False, "encoding": "latin-1"}
        if max_rows_per_file is not None:
            read_kw["nrows"] = int(max_rows_per_file)
        if p.suffix.lower() == ".csv":
            df = pd.read_csv(p, **read_kw)
        elif p.suffix.lower() in (".txt", ".tsv"):
            read_kw["sep"] = "\t"
            df = pd.read_csv(p, **read_kw)
        else:
            continue
        df["_source_file"] = p.name
        frames.append(df)
    if not frames:
        raise FileNotFoundError("No UCMR CSV/TSV files found.")
    out = pd.concat(frames, ignore_index=True)
    return out


def build_analyte_name_lookup(bridge: pd.DataFrame) -> pd.DataFrame:
    """
    Map normalized analyte names (preferred_name + split synonyms) to bridge CAS/DTXSID.
    First row wins on duplicate analyte_key.
    """
    required = {"cas_key", "dtxsid_norm", "casrn"}
    if not required.issubset(bridge.columns):
        return pd.DataFrame(columns=["analyte_key", "bridge_cas_key", "bridge_dtxsid_nm", "bridge_casrn_nm"])
    pref_col = detect_column(
        bridge,
        ["preferred_name", "preferredname", "chemical_name", "name", "analyte_name", "chemical"],
    )
    syn_col = detect_column(bridge, ["synonyms", "synonym", "alt_names", "aka", "aliases"])
    if not pref_col and not syn_col:
        return pd.DataFrame(columns=["analyte_key", "bridge_cas_key", "bridge_dtxsid_nm", "bridge_casrn_nm"])

    rows: list[dict[str, str]] = []
    for _, r in bridge.iterrows():
        cas_key = str(r.get("cas_key", "") or "").strip()
        if not cas_key:
            continue
        dtx = str(r.get("dtxsid_norm", "") or "").strip()
        casrn = str(r.get("casrn", "") or "").strip()
        names: list[str] = []
        if pref_col:
            v = r.get(pref_col)
            if v is not None and str(v).strip() and str(v).strip().lower() not in ("nan", "none"):
                names.append(str(v).strip())
        if syn_col:
            raw = r.get(syn_col)
            if raw is not None and str(raw).strip():
                for part in re.split(r"[|;,\n]", str(raw)):
                    p = part.strip()
                    if p:
                        names.append(p)
        seen_local: set[str] = set()
        for n in names:
            for ak in analyte_name_aliases(n):
                if not ak or ak in seen_local:
                    continue
                seen_local.add(ak)
                rows.append(
                    {
                        "analyte_key": ak,
                        "bridge_cas_key": cas_key,
                        "bridge_dtxsid_nm": dtx,
                        "bridge_casrn_nm": casrn,
                    }
                )

    if not rows:
        return pd.DataFrame(columns=["analyte_key", "bridge_cas_key", "bridge_dtxsid_nm", "bridge_casrn_nm"])
    df = pd.DataFrame(rows)
    dup_n = int(df["analyte_key"].duplicated().sum())
    df = df.drop_duplicates(subset=["analyte_key"], keep="first")
    df.attrs["duplicate_name_keys_collapsed"] = dup_n
    return df


def load_bridge(path: Path) -> pd.DataFrame:
    b = pd.read_csv(path, dtype=str, low_memory=False)
    need = {"casrn"}
    lower = {c.lower(): c for c in b.columns}
    if not need.issubset(set(lower.keys())):
        # allow CAS or cas_rn
        if "cas" in lower:
            b = b.rename(columns={lower["cas"]: "casrn"})
        elif "cas_rn" in lower:
            b = b.rename(columns={lower["cas_rn"]: "casrn"})
    if "dtxsid" not in {c.lower() for c in b.columns} and "dsstox_substance_id" in {c.lower() for c in b.columns}:
        ds = {c.lower(): c for c in b.columns}["dsstox_substance_id"]
        b = b.rename(columns={ds: "dtxsid"})
    b.columns = [c.strip() for c in b.columns]
    return b


def load_limits(path: Path) -> pd.DataFrame:
    lim = pd.read_csv(path, dtype=str, low_memory=False)
    lim.columns = [c.strip() for c in lim.columns]
    if "limit_ng_l" not in lim.columns:
        raise ValueError("limits file must contain column limit_ng_l")
    if "casrn" not in lim.columns and "CASRN" not in lim.columns:
        raise ValueError("limits file must contain casrn (or CASRN)")
    ccol = "casrn" if "casrn" in lim.columns else "CASRN"
    lim = lim.rename(columns={ccol: "casrn"})
    lim["limit_ng_l"] = pd.to_numeric(lim["limit_ng_l"], errors="coerce")
    lim["cas_key"] = lim["casrn"].map(normalize_cas_key)
    lim = lim[lim["cas_key"].astype(str).str.len() > 0].copy()
    # Strictest interpretive floor: minimum MCL in ng/L (lower limit = easier to exceed) — use min per cas_key
    lim = lim.groupby("cas_key", as_index=False).agg(limit_ng_l=("limit_ng_l", "min"))
    return lim


def default_bridge_csv_path(root: Path) -> Path:
    """Resolve default bridge path: same order as scripts/run_ucmr_dataset_pipeline.R (comptox, then compontox)."""
    c1 = root / "data" / "external" / "comptox" / "pfasmaster_bridge.csv"
    c2 = root / "data" / "external" / "compontox" / "pfasmaster_bridge.csv"
    if c1.is_file():
        return c1
    if c2.is_file():
        return c2
    return c1


UCMR_GLOB_DEFAULT = "__default_ucmr_csv_txt__"


def discover_ucmr_files(ucmr_dir: Path, glob_pat: str) -> list[Path]:
    """Resolve UCMR inputs. Default includes .csv and .txt (EPA occurrence zip ships tabular .txt)."""
    if not ucmr_dir.is_dir():
        return []
    if glob_pat == UCMR_GLOB_DEFAULT:
        seen: dict[str, Path] = {}
        for pat in ("*.csv", "*.txt", "*.CSV", "*.TXT"):
            for p in ucmr_dir.glob(pat):
                if not p.is_file():
                    continue
                n = p.name.lower()
                if n.startswith("readme") or n.endswith("status.json"):
                    continue
                seen[str(p.resolve())] = p
        return sorted(seen.values(), key=lambda x: (x.suffix.lower(), x.name.lower()))
    # pathlib: ** walks nested dirs (Python 3.11+); non-recursive globs stay shallow.
    return sorted(ucmr_dir.glob(glob_pat))


def _ucmr_glob_cli_default() -> str:
    v = os.environ.get("PFAS_UCMR_GLOB")
    if v is None:
        return UCMR_GLOB_DEFAULT
    v = str(v).strip()
    return v if v else UCMR_GLOB_DEFAULT


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-root",
        "--repo-root",
        default=".",
        help="Project root (defaults to cwd). Alias: --repo-root",
    )
    ap.add_argument(
        "--ucmr-glob",
        default=None,
        help="Glob under UCMR directory (e.g. *.txt). Default: all .csv and .txt. Env: PFAS_UCMR_GLOB.",
    )
    ap.add_argument(
        "--ucmr-dir",
        default=None,
        help="Directory containing UCMR files (default: <root>/data/external/epa_ucmr5)",
    )
    ap.add_argument(
        "--bridge-csv",
        "--bridge",
        dest="bridge_csv",
        default=os.environ.get("PFAS_BRIDGE_CSV"),
        help="Bridge CSV: casrn, dtxsid, optional preferred_name + synonyms (pipe/semicolon/comma-separated) for name-only UCMR rows.",
    )
    ap.add_argument(
        "--limits-csv",
        "--limits",
        dest="limits_csv",
        default=os.environ.get("PFAS_LIMITS_CSV"),
        help="Limits CSV (casrn + limit_ng_l). Alias: --limits. Env: PFAS_LIMITS_CSV.",
    )
    ap.add_argument("--out-csv", "--out", dest="out_csv", default=None, help="Output training CSV. Alias: --out")
    ap.add_argument("--out-parquet", default=None, action="store_true")
    ap.add_argument(
        "--max-rows-per-file",
        type=int,
        default=None,
        metavar="N",
        help="Read at most N rows from each UCMR file (smoke tests / debugging).",
    )
    args = ap.parse_args()

    root = Path(args.project_root).resolve()
    if args.ucmr_dir:
        udm = Path(args.ucmr_dir)
        ucmr_dir = udm.resolve() if udm.is_absolute() else (root / udm).resolve()
    else:
        ucmr_dir = (root / "data" / "external" / "epa_ucmr5").resolve()

    def _resolve_input(p: str | None, default: Path) -> Path:
        if p is None:
            return default
        s = str(p).strip()
        if not s:
            return default
        q = Path(s)
        return q.resolve() if q.is_absolute() else (root / q).resolve()

    bridge_path = _resolve_input(args.bridge_csv, default_bridge_csv_path(root))
    limits_path = _resolve_input(args.limits_csv, root / "data" / "config" / "ucmr_analyte_limits_ngl.csv")
    out_csv = _resolve_input(args.out_csv, root / "data" / "training" / "ucmr_exceedance_labeled.csv")
    out_manifest = root / "data" / "training" / "ucmr_exceedance_manifest.json"

    if not bridge_path.is_file():
        c1 = root / "data" / "external" / "comptox" / "pfasmaster_bridge.csv"
        c2 = root / "data" / "external" / "compontox" / "pfasmaster_bridge.csv"
        print(f"ERROR: Bridge CSV not found: {bridge_path}", file=sys.stderr)
        print("  Expected one of:", file=sys.stderr)
        print(f"    - {c1}", file=sys.stderr)
        print(f"    - {c2}", file=sys.stderr)
        print("  Copy from your other machine or expand the template (casrn, dtxsid, preferred_name, synonyms).", file=sys.stderr)
        for lbl, base in (("comptox", c1.parent), ("compontox", c2.parent)):
            tpl = base / "pfasmaster_bridge_template.csv"
            if tpl.is_file():
                print(f"  Template ({lbl}): {tpl}", file=sys.stderr)
        return 2
    if not limits_path.is_file():
        print(f"ERROR: Limits CSV not found: {limits_path}", file=sys.stderr)
        return 2

    # Resolve UCMR files (.txt included by default — EPA bulk occurrence bundle)
    if args.ucmr_glob is not None and str(args.ucmr_glob).strip():
        glob_pat = str(args.ucmr_glob).strip()
    else:
        glob_pat = _ucmr_glob_cli_default()
    ucmr_files = discover_ucmr_files(ucmr_dir, glob_pat)
    if not ucmr_files:
        shown = "all .csv and .txt" if glob_pat == UCMR_GLOB_DEFAULT else repr(glob_pat)
        print(
            f"ERROR: No UCMR files in {ucmr_dir} matching {shown}. "
            "Drop EPA occurrence tables there (e.g. Shiny step 2 / scripts/download_epa_ucmr5.R), "
            "or pass --ucmr-glob.",
            file=sys.stderr,
        )
        return 2

    ucmr = load_ucmr(ucmr_files, max_rows_per_file=args.max_rows_per_file)
    bridge = load_bridge(bridge_path)
    limits = load_limits(limits_path)

    # Harmonize bridge
    if "casrn" not in bridge.columns:
        print("ERROR: bridge must contain casrn", file=sys.stderr)
        return 2
    bcol_dtx = detect_column(bridge, ["dtxsid", "DTXSID", "dsstox_substance_id"])
    if not bcol_dtx:
        print("ERROR: bridge needs a DTXSID column (dtxsid)", file=sys.stderr)
        return 2
    bridge = bridge.rename(columns={bcol_dtx: "dtxsid"})
    bridge["cas_key"] = bridge["casrn"].map(normalize_cas_key)
    bridge["dtxsid_norm"] = bridge["dtxsid"].map(normalize_dtxsid)
    bridge_f = bridge[bridge["cas_key"].astype(str).str.len() > 0].copy()
    bridge_f = bridge_f[bridge_f["dtxsid_norm"].astype(str).str.len() > 0].copy()
    dup_cas = int(bridge_f["cas_key"].duplicated().sum())
    bridge_f = bridge_f.drop_duplicates(subset=["cas_key"], keep="first")
    if bridge_f.empty:
        print("ERROR: Bridge has no usable rows (need casrn + non-empty dtxsid).", file=sys.stderr)
        return 2

    # UCMR column detection
    col_contaminant = detect_column(
        ucmr,
        ["Contaminant", "contaminant", "Analyte", "Chemical Name", "Parameter", "Constituent"],
    )
    col_result = detect_column(
        ucmr,
        [
            "AnalyticalResultValue",
            "Sample Measurement",
            "Result",
            "sample_measurement",
            "Value",
            "Concentration",
            "Result Value",
        ],
    )
    col_sign = detect_column(ucmr, ["AnalyticalResultsSign", "analyticalresultssign", "Result Sign", "Qualifier"])
    col_unit = detect_column(ucmr, ["Units", "Unit", "units", "UOM"])
    col_cas = detect_column(ucmr, ["CASRN", "CAS", "casrn", "Contaminant CAS ID"])
    col_dtx = detect_column(ucmr, ["DTXSID", "dtxsid", "DSSTox_Substance_Id"])
    col_pws = detect_column(ucmr, ["PWSID", "PWS ID", "pwsid"])
    col_date = detect_column(
        ucmr,
        ["Sample Collection Date", "Collection Date", "Sample_Date", "sample_date", "Date"],
    )
    col_sample = detect_column(ucmr, ["Sample ID", "Lab Sample ID", "sample_id"])

    if not col_contaminant:
        print("ERROR: Could not detect contaminant/analyte column in UCMR.", file=sys.stderr)
        print(f"  Columns: {list(ucmr.columns)[:40]} ...", file=sys.stderr)
        return 3
    if not col_result:
        print("ERROR: Could not detect numeric result column in UCMR.", file=sys.stderr)
        return 3

    work = pd.DataFrame(
        {
            "analyte_raw": ucmr[col_contaminant].astype(str),
            "result_raw": ucmr[col_result].astype(str),
            "unit_raw": ucmr[col_unit].astype(str) if col_unit else "",
            "casrn_ucmr": ucmr[col_cas].astype(str) if col_cas else "",
            "dtxsid_ucmr": ucmr[col_dtx].astype(str) if col_dtx else "",
            "pwsid": ucmr[col_pws].astype(str) if col_pws else "",
            "sample_id": ucmr[col_sample].astype(str) if col_sample else "",
            "collection_date": ucmr[col_date].astype(str) if col_date else "",
            "sign_raw": ucmr[col_sign].astype(str) if col_sign else "",
            "_source_file": ucmr["_source_file"].astype(str)
            if "_source_file" in ucmr.columns
            else ucmr_files[0].name,
        }
    )

    work["cas_key"] = work["casrn_ucmr"].map(normalize_cas_key)
    work["dtxsid_ucmr_norm"] = work["dtxsid_ucmr"].map(normalize_dtxsid)
    work["analyte_key"] = work["analyte_raw"].map(normalize_analyte_key)

    name_lk = build_analyte_name_lookup(bridge_f)
    name_lk_rows = int(len(name_lk))

    merged = work.merge(bridge_f[["cas_key", "dtxsid_norm", "casrn"]], on="cas_key", how="left")
    merged = merged.merge(name_lk, on="analyte_key", how="left")
    if len(name_lk):
        work_compact = work.assign(analyte_key=work["analyte_key"].str.replace(" ", "", regex=False))
        mcompact = work_compact.merge(name_lk, on="analyte_key", how="left")
        for col in ("bridge_cas_key", "bridge_dtxsid_nm", "bridge_casrn_nm"):
            merged[col] = merged[col].combine_first(mcompact[col])

    matched_cas = merged["dtxsid_norm"].notna()
    matched_name = (~matched_cas) & merged["bridge_dtxsid_nm"].notna() & (merged["bridge_dtxsid_nm"].astype(str).str.len() > 0)
    merged["bridge_match_via"] = np.where(matched_cas, "cas", np.where(matched_name, "name", "none"))

    merged["dtxsid_joined"] = merged["dtxsid_norm"].fillna(merged["bridge_dtxsid_nm"])
    merged["casrn_from_bridge"] = merged["casrn"].fillna(merged["bridge_casrn_nm"])

    _ck_ucmr = merged["cas_key"].fillna("").astype(str)
    _ck_bn = merged["bridge_cas_key"].fillna("").astype(str)
    merged["cas_key_effective"] = np.where(_ck_ucmr.str.len() > 0, _ck_ucmr, _ck_bn)
    merged["cas_key_effective"] = merged["cas_key_effective"].map(normalize_cas_key)

    merged["bridge_matched"] = merged["dtxsid_joined"].notna() & (merged["dtxsid_joined"].astype(str).str.len() > 0)

    a = merged["dtxsid_ucmr_norm"].fillna("").astype(str)
    b = merged["dtxsid_joined"].fillna("").astype(str)
    merged["dtxsid_agreement"] = np.where(
        a.str.len() == 0,
        True,
        np.where(b.str.len() == 0, False, a.values == b.values),
    )

    # Non-detect: EPA UCMR signs (< vs =) plus free-text heuristics
    rlow = merged["result_raw"].str.lower().str.strip()
    nondetect = rlow.str.contains(r"^<|non-detect|nondetect|not detected|nd\b", regex=True, na=False)
    if "sign_raw" in merged.columns and merged["sign_raw"].astype(str).str.strip().ne("").any():
        sig = merged["sign_raw"].astype(str).str.strip()
        nondetect = nondetect | sig.eq("<")
    merged["nondetect_flag"] = nondetect.astype(int)

    # Parse numeric result (strip <, commas)
    def parse_result(x: str) -> float | None:
        if x is None or (isinstance(x, float) and pd.isna(x)):
            return None
        s = str(x).strip()
        s = re.sub(r"^<\s*", "", s)
        s = re.sub(r",", "", s)
        try:
            return float(s)
        except Exception:
            return None

    merged["result_num"] = merged["result_raw"].map(parse_result)
    units_series = merged["unit_raw"] if col_unit else pd.Series([""] * len(merged))
    conc_pairs = [to_ng_per_l(rn, ur) for rn, ur in zip(merged["result_num"], units_series)]
    merged["conc_ng_l"] = [p[0] for p in conc_pairs]
    merged["conc_note"] = [p[1] for p in conc_pairs]

    lim_merge = limits.rename(columns={"cas_key": "lim_cas_key"})
    merged = merged.merge(lim_merge, left_on="cas_key_effective", right_on="lim_cas_key", how="left")
    merged = merged.drop(columns=["lim_cas_key"], errors="ignore")

    lim = pd.to_numeric(merged["limit_ng_l"], errors="coerce").to_numpy()
    conc = pd.to_numeric(merged["conc_ng_l"], errors="coerce").to_numpy()
    nd = merged["nondetect_flag"].to_numpy(dtype=int)
    flag = np.full(len(merged), -1, dtype=int)
    flag[nd == 1] = 0
    ok = (nd != 1) & np.isfinite(conc) & np.isfinite(lim)
    flag[ok] = (conc[ok] >= lim[ok]).astype(int)
    merged["PFAS_Risk_Flag"] = flag

    out_dir = out_csv.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    merged_out = merged.rename(
        columns={
            "PFAS_Risk_Flag": "PFAS_Risk_Flag",
        }
    )

    keep_cols = [
        "cas_key",
        "cas_key_effective",
        "bridge_match_via",
        "casrn_ucmr",
        "casrn_from_bridge",
        "dtxsid_joined",
        "dtxsid_ucmr_norm",
        "dtxsid_agreement",
        "bridge_matched",
        "analyte_raw",
        "analyte_key",
        "pwsid",
        "sample_id",
        "collection_date",
        "result_raw",
        "result_num",
        "unit_raw",
        "conc_ng_l",
        "conc_note",
        "limit_ng_l",
        "nondetect_flag",
        "PFAS_Risk_Flag",
        "_source_file",
    ]
    keep_cols = [c for c in keep_cols if c in merged_out.columns]
    final_df = merged_out[keep_cols].copy()

    final_df.to_csv(out_csv, index=False)

    ucmr_dtx = final_df["dtxsid_ucmr_norm"].fillna("").astype(str).str.len() > 0
    disagree = ucmr_dtx & (~final_df["dtxsid_agreement"].astype(bool))
    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "project_root": str(root),
        "inputs": {
            "ucmr_files": [str(p) for p in ucmr_files],
            "max_rows_per_file": args.max_rows_per_file,
            "ucmr_rows": int(len(ucmr)),
            "bridge_csv": str(bridge_path),
            "bridge_sha256": _sha256_file(bridge_path),
            "bridge_duplicate_cas_rows_collapsed": int(dup_cas),
            "bridge_name_lookup_rows": int(name_lk_rows),
            "limits_csv": str(limits_path),
            "limits_sha256": _sha256_file(limits_path),
        },
        "outputs": {
            "training_csv": str(out_csv),
            "labeled_rows": int(len(final_df)),
            "labeled_distribution": final_df["PFAS_Risk_Flag"].value_counts(dropna=False).to_dict(),
            "bridge_match_rate": float(final_df["bridge_matched"].astype(bool).mean()) if len(final_df) else 0.0,
            "bridge_match_via_counts": final_df["bridge_match_via"].value_counts(dropna=False).to_dict()
            if "bridge_match_via" in final_df.columns
            else {},
            "ucmr_dtxsid_disagreement_rate": float(disagree.mean()) if len(final_df) else 0.0,
        },
        "definition": {
            "join_keys": [
                "cas_key (digits-only CAS from UCMR when present)",
                "analyte_key: normalized Contaminant name ↔ bridge preferred_name/synonyms",
                "limit merge on cas_key_effective (CAS from row or from name bridge)",
            ],
            "target": "PFAS_Risk_Flag: 1 if conc_ng_l >= limit_ng_l for cas_key_effective; 0 if nondetect_flag; -1 if no limit or unparseable conc",
            "outputs_layout": "single_merged_training_table",
            "python": sys.version.split()[0],
            "pandas": pd.__version__,
        },
    }
    out_manifest.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    if args.out_parquet and _HAS_ARROW:
        pq_path = out_csv.with_suffix(".parquet")
        final_df.to_parquet(pq_path, index=False)
        manifest["outputs"]["training_parquet"] = str(pq_path)
        out_manifest.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(json.dumps(manifest["outputs"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
