"""
Hybrid PFAS encoder — vector stage (SMILES descriptors + measurement context).

Step 1 of graphs + descriptors + context + measurement_flags: produces a fixed-width
numpy vector suitable for stacking with a future graph latent vector.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple, TypedDict


def _require_rdkit():
    try:
        from rdkit import Chem  # noqa: F401
        from rdkit.Chem import Descriptors  # noqa: F401

        return True
    except ImportError:
        return False


# Bump when descriptor set, fingerprint width, or measurement block layout changes (audit / parquet rebuilds).
ENCODER_SEMANTIC_VERSION = "0.2.0"
# Logical name for reproducibility payloads (pairs with ENC OS / model cards later).
DESCRIPTOR_BLOCK_ID = "rdkit_lipinski_extended_pfassmart_v1"
MORGAN_BLOCK_ID_TEMPLATE = "morgan_ecfp_radius_{radius}_bits_{bits}"


def encoder_provenance(
    *,
    include_morgan: bool = True,
    morgan_bits: int = 256,
    morgan_radius: int = 2,
) -> Dict[str, Any]:
    """Pinned metadata for regulatory / QMS payloads (expand with PubChem CID, DTXSID at ingest time)."""

    pv: Dict[str, Any] = {
        "encoder_semantic_version": ENCODER_SEMANTIC_VERSION,
        "descriptor_block_id": DESCRIPTOR_BLOCK_ID,
        "python_implementation_module": __name__,
        "descriptor_dim": len(DESCRIPTOR_FUNCTIONS),
        "measurement_block_width": measurement_block_width(),
        "hybrid_vector_dim": hybrid_encoder_output_dim(
            include_morgan=include_morgan, morgan_bits=morgan_bits
        ),
    }
    if include_morgan:
        pv["morgan_block_id"] = MORGAN_BLOCK_ID_TEMPLATE.format(
            radius=int(morgan_radius), bits=int(morgan_bits)
        )
    try:
        import rdkit

        pv["rdkit_version"] = getattr(rdkit, "__version__", "unknown")
    except ImportError:
        pv["rdkit_version"] = None
    return pv


def apply_matrix_group_flags_inplace(df: "Any", matrix_col: str) -> "Any":
    """
    One-hot style matrix lane flags from ``matrix_col`` (aligned with :func:`recipes.matrix_class.matrix_route_key`):

    - **water** → ``matrix_drinking_water``
    - **serum** → ``matrix_serum``
    - **air** → ``matrix_air``
    - **solids** → ``matrix_solids``
    - **other** → ``matrix_other`` only

    Reserved for a later layout bump: ``matrix_food``, ``matrix_fish`` (routes not wired yet).
    """

    from recipes.matrix_class import matrix_route_key

    out = df
    ww, ss, aa, sol, oo = [], [], [], [], []
    for v in df[matrix_col].tolist():
        r = matrix_route_key(v)
        ww.append(r == "water")
        ss.append(r == "serum")
        aa.append(r == "air")
        sol.append(r == "solids")
        oo.append(r == "other")
    out["matrix_drinking_water"] = ww
    out["matrix_serum"] = ss
    out["matrix_air"] = aa
    out["matrix_solids"] = sol
    out["matrix_other"] = oo
    return out


# Ordered list aligned with toxicity/chem informatics dashboards; keep stable for model cards.
DESCRIPTOR_FUNCTIONS: Tuple[Tuple[str, str], ...] = (
    ("desc_MolWt", "MolWt"),
    ("desc_MolLogP", "MolLogP"),
    ("desc_TPSA", "TPSA"),
    ("desc_NumHDonors", "NumHDonors"),
    ("desc_NumHAcceptors", "NumHAcceptors"),
    ("desc_NumRotatableBonds", "NumRotatableBonds"),
    ("desc_NumAromaticRings", "NumAromaticRings"),
    ("desc_NumAliphaticRings", "NumAliphaticRings"),
    ("desc_NumSaturatedRings", "NumSaturatedRings"),
    ("desc_HeavyAtomCount", "HeavyAtomCount"),
    ("desc_NumHeteroatoms", "NumHeteroatoms"),
    ("desc_FractionCSP3", "FractionCSP3"),
    ("desc_NumFluorine", "NumFluorine"),
    ("desc_NumSulfones", "_count_sulfonyl_approx"),
    ("desc_FormalCharge", "FormalCharge_rdkit"),
)

# Measurement tail: single source for names count (v0.2 adds air/solids lanes; food/fish reserved).
MEASUREMENT_BLOCK_NAMES: List[str] = [
    "meas_quantity_raw_log1p",
    "meas_is_non_detect",
    "meas_is_left_censored_imputed",
    "meas_substitute_factor_vs_limit",
    "meas_limit_log1p",
    "meas_has_positive_limit",
    "meas_quant_was_reported_numeric",
    "meas_result_on_log10_scale",
    "meas_flag_matrix_drinking_water",
    "meas_flag_matrix_serum",
    "meas_flag_matrix_air",
    "meas_flag_matrix_solids",
    "meas_flag_matrix_other",
    "meas_flag_qa_compromised",
    "meas_flag_technical_replicate",
    "meas_flag_surrogate_recovery_fail",
    "meas_flag_diluted",
]


def measurement_block_width() -> int:
    """Count of measurement scalars in the HybridVectorEncoder vector tail."""

    return len(MEASUREMENT_BLOCK_NAMES)


def hybrid_encoder_output_dim(
    *,
    include_morgan: bool = True,
    morgan_bits: int = 256,
) -> int:
    """Total HybridVectorEncoder feature width — descriptors + optional Morgan + ``MEASUREMENT_BLOCK_NAMES``."""

    n = len(DESCRIPTOR_FUNCTIONS)
    if include_morgan:
        n += int(morgan_bits)
    return n + measurement_block_width()

# Fallback when SMARTS/count helpers fail — keep vector width stable.


def _count_fluorine(mol) -> float:
    from rdkit import Chem

    n = 0
    for a in mol.GetAtoms():
        if a.GetAtomicNum() == Chem.Fluorine.GetAtomicNum():
            n += 1
    return float(n)


def _count_sulfonyl_approx(mol) -> float:
    """Approximate S(=O)(=O) count via SMARTS (sulfonic / sulfonamide style)."""
    from rdkit import Chem

    patt = Chem.MolFromSmarts("S(=O)(=O)")
    if patt is None:
        return 0.0
    return float(len(mol.GetSubstructMatches(patt)))


def _descriptor_value(mol, key: str) -> float:
    from rdkit.Chem import Descriptors, Lipinski

    if key == "MolWt":
        return float(Descriptors.MolWt(mol))
    if key == "MolLogP":
        return float(Descriptors.MolLogP(mol))
    if key == "TPSA":
        return float(Descriptors.TPSA(mol))
    if key == "NumHDonors":
        return float(Lipinski.NumHDonors(mol))
    if key == "NumHAcceptors":
        return float(Lipinski.NumHAcceptors(mol))
    if key == "NumRotatableBonds":
        return float(Lipinski.NumRotatableBonds(mol))
    if key == "NumAromaticRings":
        return float(Lipinski.NumAromaticRings(mol))
    if key == "NumAliphaticRings":
        return float(Lipinski.NumAliphaticRings(mol))
    if key == "NumSaturatedRings":
        return float(Lipinski.NumSaturatedRings(mol))
    if key == "HeavyAtomCount":
        return float(Descriptors.HeavyAtomCount(mol))
    if key == "NumHeteroatoms":
        return float(Lipinski.NumHeteroatoms(mol))
    if key == "FractionCSP3":
        return float(Lipinski.FractionCSP3(mol))
    if key == "NumFluorine":
        return _count_fluorine(mol)
    if key == "_count_sulfonyl_approx":
        return _count_sulfonyl_approx(mol)
    if key == "FormalCharge_rdkit":
        return float(Chem_GetFormalCharge(mol))
    raise KeyError(key)


def Chem_GetFormalCharge(mol) -> int:
    from rdkit import Chem

    return Chem.GetFormalCharge(mol)


def morgan_numpy(mol, radius: int = 2, n_bits: int = 256) -> "Any":
    from rdkit.Chem.AllChem import GetMorganFingerprintAsBitVect

    # Older RDKit Boost bindings expect `nBits` as the 3rd positional arg (not kw-only).
    bv = GetMorganFingerprintAsBitVect(mol, int(radius), int(n_bits))
    return _bitvect_to_numpy(bv, n_bits)


def _bitvect_to_numpy(bv, n_bits: int):
    import numpy as np

    arr = np.zeros((n_bits,), dtype=np.float32)
    on = bv.GetOnBits()
    for i in on:
        if 0 <= i < n_bits:
            arr[i] = 1.0
    return arr


@dataclass
class MeasurementRow:
    """Per-row laboratory / reporting context."""

    quant_value: Optional[float] = None
    lod: Optional[float] = None
    reporting_limit: Optional[float] = None
    is_non_detect: bool = False
    imputation: str = "half_lod"  # half_lod | lod | sqrt_half_lod | nan
    result_log10_scaled: bool = False
    matrix_drinking_water: bool = False
    matrix_serum: bool = False
    matrix_air: bool = False
    matrix_solids: bool = False
    matrix_other: bool = False
    # matrix_food / matrix_fish: reserved for ingest routing + MEASUREMENT_BLOCK_NAMES (vNext).
    qa_sample_compromised: bool = False
    duplicate_technical_replicate: bool = False
    surrogate_recovery_fail: bool = False
    diluted_sample: bool = False

    def effective_limit(self) -> Optional[float]:
        candidates = []
        for x in (self.reporting_limit, self.lod):
            if x is None:
                continue
            try:
                v = float(x)
            except (TypeError, ValueError):
                continue
            if v > 0 and math.isfinite(v):
                candidates.append(v)
        if not candidates:
            return None
        return max(candidates)


@dataclass
class EncodingResult:
    vector: "Any"
    feature_names: List[str]
    meta: Dict[str, Any]


class FeatureSchema(TypedDict):
    descriptors: List[str]
    fingerprint: List[str]
    measurements: List[str]


class HybridVectorEncoder:
    """
    Builds [RDKit descriptors] + optional [Morgan bits] + [measurement scalars / flags].

    Measurement channel:
    - Always emits masking flags so censoring is explicit.
    - For model input, emits `meas_log1p_quantity` using user quant or imputed substitute.
    """

    def __init__(self, morgan_bits: int = 256, morgan_radius: int = 2, include_morgan: bool = True):
        import numpy as np

        self._np = np
        self.morgan_bits = int(morgan_bits)
        self.morgan_radius = int(morgan_radius)
        self.include_morgan = bool(include_morgan)

    def feature_schema(self) -> FeatureSchema:
        desc_names = [n for n, _ in DESCRIPTOR_FUNCTIONS]
        fp_names: List[str] = []
        if self.include_morgan:
            fp_names = [f"fp_morgan_r{self.morgan_radius}_{i}" for i in range(self.morgan_bits)]

        return {
            "descriptors": desc_names,
            "fingerprint": fp_names,
            "measurements": list(MEASUREMENT_BLOCK_NAMES),
        }

    def all_feature_names(self) -> List[str]:
        sch = self.feature_schema()
        return sch["descriptors"] + sch["fingerprint"] + sch["measurements"]

    def encode(
        self,
        smiles: str,
        measurements: Optional[MeasurementRow] = None,
        *,
        fail_on_bad_smiles: bool = False,
    ) -> EncodingResult:
        if not _require_rdkit():
            raise ImportError(
                "RDKit is required. Install via `pip install rdkit` or conda-forge (`conda install -c conda-forge rdkit`)."
            )
        from rdkit import Chem

        import numpy as np

        measurements = measurements or MeasurementRow()

        mol = Chem.MolFromSmiles(smiles or "")
        ok = mol is not None
        meta: Dict[str, Any] = {"smiles_parse_ok": ok, "smiles": smiles}

        desc = np.zeros((len(DESCRIPTOR_FUNCTIONS),), dtype=np.float32)
        if ok:
            for i, (_, fn_key) in enumerate(DESCRIPTOR_FUNCTIONS):
                try:
                    desc[i] = np.float32(_descriptor_value(mol, fn_key))
                except Exception:
                    desc[i] = np.float32("nan")

        if self.include_morgan:
            if ok:
                fp = morgan_numpy(mol, radius=self.morgan_radius, n_bits=self.morgan_bits)
            else:
                fp = np.zeros((self.morgan_bits,), dtype=np.float32)
        else:
            fp = np.zeros((0,), dtype=np.float32)

        ms_row, ms_meta = _encode_measurement_block(measurements, self._np)
        meta.update(ms_meta)

        vec = np.concatenate([desc.astype(np.float32), fp.astype(np.float32), ms_row], axis=0)
        names = self.all_feature_names()
        assert vec.shape[0] == len(names), (vec.shape[0], len(names))

        if fail_on_bad_smiles and not ok:
            raise ValueError("Invalid SMILES for HybridVectorEncoder.encode")

        return EncodingResult(vector=vec, feature_names=names, meta=meta)


def _encode_measurement_block(row: MeasurementRow, np_module) -> Tuple["Any", Dict[str, Any]]:
    meta: Dict[str, Any] = {}
    np = np_module

    lim = row.effective_limit()
    has_lim = lim is not None and lim > 0 and math.isfinite(lim)

    qty = row.quant_value
    quant_reported = qty is not None and math.isfinite(float(qty)) and float(qty) >= 0
    nd = bool(row.is_non_detect) or (not quant_reported and has_lim)

    imputation = str(row.imputation or "half_lod").lower()
    substitute_used = nd and has_lim
    substitute_factor = np.float32(math.nan)

    resolved = math.nan
    if quant_reported:
        resolved = float(qty)
        meta["measurement_substitution"] = "none"
    elif substitute_used and imputation == "lod":
        resolved = float(lim)
        substitute_factor = np.float32(1.0)
        meta["measurement_substitution"] = "lod"
    elif substitute_used and imputation == "half_lod":
        resolved = 0.5 * float(lim)
        substitute_factor = np.float32(0.5)
        meta["measurement_substitution"] = "half_lod"
    elif substitute_used and imputation in ("sqrt_half_lod", "dl_over_sqrt2", "lod_over_sqrt2"):
        resolved = float(lim) / math.sqrt(2.0)
        substitute_factor = np.float32(1.0 / math.sqrt(2.0))
        meta["measurement_substitution"] = "sqrt_half_lod"
    elif substitute_used and imputation == "nan":
        resolved = math.nan
        substitute_factor = np.float32(math.nan)
        meta["measurement_substitution"] = "nan_explicit"
    else:
        meta["measurement_substitution"] = "missing"

    meas_log1p = np.float32(math.nan)
    lim_log1p = np.float32(math.log1p(lim)) if has_lim else np.float32(math.nan)
    if math.isfinite(resolved) and resolved >= 0:
        meas_log1p = np.float32(math.log1p(resolved))

    block = np.array(
        [
            meas_log1p,
            np.float32(1.0 if nd else 0.0),
            np.float32(1.0 if substitute_used and imputation != "nan" else 0.0),
            substitute_factor if math.isfinite(float(substitute_factor)) else np.float32(math.nan),
            lim_log1p,
            np.float32(1.0 if has_lim else 0.0),
            np.float32(1.0 if quant_reported else 0.0),
            np.float32(1.0 if row.result_log10_scaled else 0.0),
            np.float32(1.0 if row.matrix_drinking_water else 0.0),
            np.float32(1.0 if row.matrix_serum else 0.0),
            np.float32(1.0 if row.matrix_air else 0.0),
            np.float32(1.0 if row.matrix_solids else 0.0),
            np.float32(1.0 if row.matrix_other else 0.0),
            np.float32(1.0 if row.qa_sample_compromised else 0.0),
            np.float32(1.0 if row.duplicate_technical_replicate else 0.0),
            np.float32(1.0 if row.surrogate_recovery_fail else 0.0),
            np.float32(1.0 if row.diluted_sample else 0.0),
        ],
        dtype=np.float32,
    )
    assert block.shape[0] == measurement_block_width(), (block.shape[0], measurement_block_width())

    meta["limit_value"] = lim
    meta["is_non_detect"] = nd
    return block, meta


def encode_batch_table(
    df,
    smiles_col: str = "SMILES",
    encoder: Optional[HybridVectorEncoder] = None,
) -> "Any":
    """Convenience: pandas DataFrame -> matrix (n_rows, n_features)."""
    enc = encoder or HybridVectorEncoder()
    rows = []
    names: Optional[List[str]] = None
    metas: List[Dict[str, Any]] = []
    for _, r in df.iterrows():
        smi = r.get(smiles_col, "")
        mr = measurement_from_series(r)
        out = enc.encode(str(smi) if smi is not None else "", mr)
        rows.append(out.vector)
        names = out.feature_names
        metas.append(out.meta)
    import numpy as np

    return np.stack(rows, axis=0), names, metas


def _opt_scalar_float(row, key_candidates: Sequence[str]) -> Optional[float]:
    for k in key_candidates:
        if k not in row or row[k] is None:
            continue
        v = row[k]
        if hasattr(v, "item"):
            try:
                v = v.item()
            except Exception:
                pass
        if isinstance(v, str) and not v.strip():
            continue
        try:
            x = float(v)
            if math.isfinite(x):
                return x
        except (TypeError, ValueError):
            continue
    return None


def _row_get(r, key: str, default=None):
    """pandas Series–safe get."""
    if hasattr(r, "get"):
        try:
            return r.get(key, default)
        except Exception:
            pass
    try:
        return r[key] if key in r else default
    except Exception:
        return default


def measurement_from_series(r: Mapping[str, Any]) -> MeasurementRow:
    q = _opt_scalar_float(r, ("quant_value", "conc", "result_value", "concentration", "meas_conc"))

    lod = _opt_scalar_float(r, ("lod", "mdl", "method_detection_limit"))
    rl = _opt_scalar_float(r, ("reporting_limit", "reporting_RL", "practical_quantitation_limit", "pql"))

    nd_v = _row_get(r, "is_non_detect", None)
    if nd_v is None:
        nd_v = _row_get(r, "non_detect", _row_get(r, "detect_flag", None))
    if isinstance(nd_v, str):
        sl = nd_v.strip().lower()
        if sl in {"nd", "<", "censored", "yes", "y", "true", "1"}:
            nd_v = True
        elif sl in {"detect", "d", "no", "n", "false", "0"}:
            nd_v = False

    try:
        is_nd = bool(int(nd_v)) if nd_v is not None and not isinstance(nd_v, bool) else bool(nd_v)
    except Exception:
        is_nd = str(nd_v).strip().lower() in {"1", "true", "yes", "y"}

    impl_v = _row_get(r, "imputation", None)
    impl_s = str(impl_v if impl_v is not None else "half_lod") or "half_lod"

    return MeasurementRow(
        quant_value=q,
        lod=lod,
        reporting_limit=rl,
        is_non_detect=is_nd,
        imputation=impl_s,
        result_log10_scaled=bool(_row_get(r, "result_log10_scaled", False)),
        matrix_drinking_water=bool(_row_get(r, "matrix_drinking_water", False)),
        matrix_serum=bool(_row_get(r, "matrix_serum", False)),
        matrix_air=bool(_row_get(r, "matrix_air", False)),
        matrix_solids=bool(_row_get(r, "matrix_solids", False)),
        matrix_other=bool(_row_get(r, "matrix_other", False)),
        qa_sample_compromised=bool(_row_get(r, "qa_sample_compromised", False)),
        duplicate_technical_replicate=bool(_row_get(r, "duplicate_technical_replicate", False)),
        surrogate_recovery_fail=bool(_row_get(r, "surrogate_recovery_fail", False)),
        diluted_sample=bool(_row_get(r, "diluted_sample", False)),
    )


def encode_batch_with_meta(df: "Any", smiles_col: str = "SMILES", encoder: Optional[HybridVectorEncoder] = None):
    """Returns `(features_df float32, list[meta dict per row])`."""

    import numpy as np
    import pandas as pd

    X, colnames, metas = encode_batch_table(df, smiles_col=smiles_col, encoder=encoder)
    pdf = pd.DataFrame(X, columns=colnames).astype(np.float32)
    return pdf, metas


def _cli() -> int:
    p = argparse.ArgumentParser(description="Smoke-test PFAS hybrid vector encoder.")
    p.add_argument("--smiles", type=str, required=True)
    p.add_argument("--no-morgan", action="store_true", help="Omit Morgan fingerprint block.")
    p.add_argument("--non-detect", action="store_true")
    p.add_argument("--lod", type=float, default=None)
    p.add_argument("--quant", type=float, default=None)
    p.add_argument("--imputation", type=str, default="half_lod", choices=("half_lod", "lod", "nan", "sqrt_half_lod"))
    p.add_argument("--json", action="store_true", help="Print meta + vector shape (not full vector).")
    args = p.parse_args()

    enc = HybridVectorEncoder(include_morgan=not args.no_morgan)
    mr = MeasurementRow(
        quant_value=args.quant,
        lod=args.lod,
        is_non_detect=args.non_detect,
        imputation=args.imputation,
        matrix_serum=True,
    )
    out = enc.encode(args.smiles, mr)
    if args.json:
        payload = {
            "meta": out.meta,
            "dim": int(out.vector.shape[0]),
            "feature_names": out.feature_names,
            "vector_head": out.vector[:12].tolist(),
        }
        print(json.dumps(payload, indent=2))
    else:
        print("dim", out.vector.shape[0])
        print("meta", out.meta)
        print("names (first 8)", out.feature_names[:8])
    return 0


if __name__ == "__main__":
    raise SystemExit(_cli())
