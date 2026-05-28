"""Smoke test: V1 reference engine loads weighted table and scores a row."""
from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))

from src.v1.ontology import load_ontology
from src.v1.reference import ReferenceEngine


def main() -> int:
    ont = load_ontology()
    engine = ReferenceEngine.load(ont)
    anchor_sha = ReferenceEngine.verify_anchor_csv(ont)
    print(f"ontology_hash={ont.ontology_hash[:16]}...")
    print(f"reference_table_sha256={engine.reference_table_sha256[:16]}...")
    print(f"anchor_csv_sha256={anchor_sha[:16]}...")
    print(f"indexed_strata={len(engine._index)}")

    r = engine.percentile("n_pfoa", 1.3)
    print(
        f"n_pfoa @ 1.3 ng/mL (cycle J, all, all_ages): "
        f"pct={r.percentile:.1f} n={r.n_reference} below_lod={r.pct_below_lod_reference:.2f}%"
    )
    assert r.percentile is not None
    assert 40 < r.percentile < 60, f"expected ~50th pct, got {r.percentile}"

    r_sb = engine.percentile("sb_pfoa", 0.07)
    print(
        f"sb_pfoa @ 0.07 ng/mL: pct={r_sb.percentile:.1f} "
        f"query_below_imputed={r_sb.query_below_imputed_lod}"
    )
    assert r_sb.query_below_imputed_lod

    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
