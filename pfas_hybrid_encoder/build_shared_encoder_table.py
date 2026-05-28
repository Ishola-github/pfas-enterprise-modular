"""
Materialize canonical tabular chemistry + measurement inputs for shared encoder training.

Primary output:
  shared_encoder_input.parquet — ID / audit columns + fixed-width feature block
                                 (`HybridVectorEncoder.all_feature_names()`: descriptors +
                                 optional Morgan + `MEASUREMENT_BLOCK_NAMES`; width is never a magic constant here).

Companion:
  shared_encoder_input_provenance.json — versions, schema ids, column order.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, List, Optional, Sequence, Set

DEFAULT_OUT = Path("results") / "shared_encoder_input.parquet"
DEFAULT_PROV = Path("results") / "shared_encoder_input_provenance.json"


def _repo_root_here() -> Path:
    """Parent of package dir (cwd for relative results/)."""
    return Path(__file__).resolve().parent


def _read_table(path: Path):
    import pandas as pd

    suf = path.suffix.lower()
    if suf in {".parquet", ".pq"}:
        return pd.read_parquet(path)
    if suf in {".csv", ".txt"}:
        return pd.read_csv(path, low_memory=False)
    raise ValueError(f"Unsupported input suffix: {suf} (use .csv or .parquet)")


def _normalize_smiles_registry(reg, analyte_col: str, smiles_col: str):
    """Return df with unique analyte_col -> smiles_col."""

    import pandas as pd

    need = [analyte_col, smiles_col]
    miss = [c for c in need if c not in reg.columns]
    if miss:
        raise ValueError(f"Registry missing columns {miss}; have {list(reg.columns)}")
    sub = reg[need].dropna(subset=[analyte_col, smiles_col])
    sub = sub.drop_duplicates(subset=[analyte_col])
    sub[analyte_col] = sub[analyte_col].astype(str).str.strip()
    return sub


def main(argv: Optional[Sequence[str]] = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    ap = argparse.ArgumentParser(description="Build shared_encoder_input.parquet from ingest table + SMILES.")
    ap.add_argument("--input", type=Path, required=True, help="CSV or parquet with sample/analyte/measurements.")
    ap.add_argument("--output", type=Path, default=DEFAULT_OUT, help=".parquet path (default results/shared_encoder_input.parquet)")
    ap.add_argument("--provenance", type=Path, default=DEFAULT_PROV, help="JSON sidecar for audit trail.")
    ap.add_argument("--smiles-col", type=str, default="SMILES", help="Column with SMILES (after optional registry merge).")
    ap.add_argument("--analyte-col", type=str, default="analyte", help="Analyte/name key for registry join.")
    ap.add_argument("--analyte-registry", type=Path, default=None, help="CSV or parquet mapping analyte -> SMILES.")
    ap.add_argument("--registry-smiles-col", type=str, default="SMILES", help="SMILES column name in registry file.")
    ap.add_argument("--derive-matrix-onehot", type=str, default=None, metavar="COL", help="If set, derive matrix_* flags from this categorical column.")
    ap.add_argument("--id-cols", type=str, default="sample_id", help="Comma-separated ID columns copied to output (must exist).")
    ap.add_argument(
        "--passthrough",
        type=str,
        default="analyte,matrix,conc_unit,collection_year,month,season,pubchem_cid,comptox_dtxsid,smiles_joined_from_registry",
        help="Comma-separated ingest columns copied when present (not required). Empty = IDs + features only.",
    )
    ap.add_argument("--no-morgan", action="store_true")
    ap.add_argument(
        "--recipe-etl-v1",
        action="store_true",
        help="Apply per-matrix ETL recipes (water_v1, serum_v1) before encoding. Requires --recipe-matrix-col or --derive-matrix-onehot.",
    )
    ap.add_argument(
        "--recipe-matrix-col",
        type=str,
        default=None,
        metavar="COL",
        help="Matrix label column used by recipe routing (defaults to same as --derive-matrix-onehot when set).",
    )
    ap.add_argument(
        "--recipe-strict-other",
        action="store_true",
        help="Fail build if matrix label is neither water-like nor serum-like (recommended for QA).",
    )
    args = ap.parse_args(list(argv))

    sys.path.insert(0, str(_repo_root_here()))
    from pfas_encoder_vector import (
        ENCODER_SEMANTIC_VERSION,
        apply_matrix_group_flags_inplace,
        encoder_provenance,
        encode_batch_with_meta,
        HybridVectorEncoder,
    )

    inp = args.input.expanduser().resolve()
    out = args.output.expanduser().resolve()
    prv = args.provenance.expanduser().resolve()
    df = _read_table(inp)

    analyte_join = args.analyte_col.strip()
    if analyte_join in df.columns:
        df[analyte_join] = df[analyte_join].astype(str).str.strip()

    smiles_col_name = args.smiles_col.strip()
    if smiles_col_name not in df.columns:
        df[smiles_col_name] = ""

    recipe_mc = (args.recipe_matrix_col or args.derive_matrix_onehot or "").strip() or None
    used_recipes = False
    recipe_suite_logged: Optional[str] = None
    if args.recipe_etl_v1:
        if not recipe_mc:
            raise ValueError("--recipe-etl-v1 requires --recipe-matrix-col and/or --derive-matrix-onehot naming the matrix column.")
        from preprocess_matrix import preprocess_for_shared_encoder
        from recipes.dispatch import RECIPE_SUITE_ID as _ETL_SID

        df = preprocess_for_shared_encoder(
            df,
            recipe_mc,
            strict_unknown_matrix=args.recipe_strict_other,
            run_validators=True,
        )
        used_recipes = True
        recipe_suite_logged = _ETL_SID

    if args.analyte_registry is not None:
        rp = args.analyte_registry.expanduser().resolve()
        reg = _read_table(rp)
        reg_small = _normalize_smiles_registry(reg, analyte_join, args.registry_smiles_col)
        df = df.merge(reg_small.rename(columns={args.registry_smiles_col: "__smiles_reg"}), on=analyte_join, how="left")
        base = df[smiles_col_name].astype(str).replace({"nan": ""}).replace("<NA>", "")
        merged = df["__smiles_reg"].where(
            df["__smiles_reg"].notna() & df["__smiles_reg"].astype(str).str.strip().ne(""), base
        )
        df[smiles_col_name] = merged.astype(str)
        df["smiles_joined_from_registry"] = df["__smiles_reg"].notna() & df["__smiles_reg"].astype(str).str.strip().ne("")
        df.drop(columns=["__smiles_reg"], inplace=True)

    if args.derive_matrix_onehot:
        mc = args.derive_matrix_onehot
        if mc not in df.columns:
            raise ValueError(f"--derive-matrix-onehot column {mc!r} not in input columns.")
        apply_matrix_group_flags_inplace(df, mc)

    id_cols = [c.strip() for c in args.id_cols.split(",") if c.strip()]
    missing_id = [c for c in id_cols if c not in df.columns]
    if missing_id:
        raise ValueError(f"Missing --id-cols in table: {missing_id}")

    pass_cols: List[str] = []
    if args.passthrough.strip():
        want = [c.strip() for c in args.passthrough.split(",") if c.strip()]
        pass_cols = [c for c in want if c in df.columns and c not in id_cols]

    augment = sorted(
        c
        for c in df.columns
        if (
            c.startswith("etl_")
            or c
            in {
                "canonical_conc_unit",
                "recipe_id",
                "imputation",
                "etl_suite_id",
            }
        )
    )
    pass_cols = sorted(set(pass_cols).union(a for a in augment if a not in id_cols))

    reserved: Set[str] = set(id_cols + pass_cols + [smiles_col_name])

    enc = HybridVectorEncoder(include_morgan=not args.no_morgan)
    feats, metas = encode_batch_with_meta(df, smiles_col=smiles_col_name, encoder=enc)

    names = enc.all_feature_names()
    clashes = sorted(reserved.intersection(names))
    if clashes:
        raise ValueError(f"Ingest columns clash with encoder feature names: {clashes}. Rename ingest columns.")

    import numpy as np
    import pandas as pd

    parse_ok = [bool(m.get("smiles_parse_ok")) for m in metas]

    pv = encoder_provenance(
        include_morgan=enc.include_morgan,
        morgan_bits=enc.morgan_bits,
        morgan_radius=enc.morgan_radius,
    )
    pv_flat = pd.DataFrame(
        {k: np.repeat("" if v is None else str(v), len(df)) for k, v in pv.items()} if pv else {},
    )

    audit = pd.DataFrame({"smiles_parse_ok": parse_ok})

    lhs = pd.concat([df[id_cols].reset_index(drop=True), df[pass_cols].reset_index(drop=True), audit.reset_index(drop=True), pv_flat.reset_index(drop=True)], axis=1)
    out_df = pd.concat([lhs.reset_index(drop=True), feats.reset_index(drop=True)], axis=1)

    out.parent.mkdir(parents=True, exist_ok=True)
    out_df.to_parquet(out, index=False)

    prov_payload = {
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_path": str(inp),
        "output_path": str(out),
        "encoder": pv,
        "encoder_semantic_version": ENCODER_SEMANTIC_VERSION,
        "n_rows": int(len(out_df)),
        "feature_columns": names,
        "feature_dim": len(names),
        "id_columns": id_cols,
        "passthrough_columns_used": pass_cols,
        "smiles_column": smiles_col_name,
        "matrix_onehot_derived_from": args.derive_matrix_onehot,
        "recipe_etl_v1_applied": used_recipes,
        "recipe_matrix_column": recipe_mc if used_recipes else None,
        "recipe_etl_suite": recipe_suite_logged,
        "recipe_strict_other": bool(args.recipe_strict_other) if used_recipes else None,
        "note_matrix_units": (
            "Concentrations in meas_* assume ingest `conc` / `quant_value` is harmonized PER MATRIX conventions "
            "(e.g., water ng/L vs serum ng/mL). This script does not interconvert ambient vs liquid units."
        ),
        "future_work": ["temporal embeddings", "comptox/pubchem ingest join at row level", "graph latent concatenation"],
    }
    prv.parent.mkdir(parents=True, exist_ok=True)
    prv.write_text(json.dumps(prov_payload, indent=2), encoding="utf-8")

    print(f"Wrote {len(out_df)} rows x {len(out_df.columns)} columns -> {out}")
    print(f"Provenance -> {prv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
