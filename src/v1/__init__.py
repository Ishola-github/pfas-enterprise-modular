"""PFAS Enterprise 5.0 -- V1.

V1 provides governed serum PFOS/PFOA contextualization against
CDC NHANES reference distributions with deterministic replay,
provenance logging, and refusal-first applicability enforcement.

V1 is NOT diagnostic, NOT clinical, NOT regulatory, NOT an
exposure-risk prediction, and NOT a toxicology AI. See
src/v1/README.md and validation/serum_v1/limitations.md for the
full non-claim register.
"""

__version__ = "1.1.0"
"""Code version. Pinned alongside the ontology version, which is
recorded separately in src/v1/data/ontology/pfos_pfoa_v1.json
under the `ontology_version` key. The two are deliberately
independent: a code-only bugfix can change __version__ without
touching the ontology hash; an ontology-only change can change
the ontology hash without touching __version__. The provenance
logger records both.
"""

ONTOLOGY_PATH = "src/v1/data/ontology/pfos_pfoa_v1.json"
"""Repo-relative path to the V1.0 frozen ontology JSON."""

ONTOLOGY_V1_1_PATH = "src/v1/data/ontology/pfos_pfoa_v1_1.json"
"""Repo-relative path to the V1.1 ontology (race/ethnicity + LOD policy)."""

REFERENCE_TABLE_PATH = (
    "data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv"
)
"""Repo-relative path to the OFFICIAL weighted NHANES reference
table consumed by the V1 reference engine at runtime."""

REFERENCE_TABLE_SHA256 = (
    "715cd8968e21c9e2404b4a10054ea44d78e52707c70d4b10289f1ba9c463e45c"
)
"""Expected SHA-256 of REFERENCE_TABLE_PATH."""

REFERENCE_TABLE_V1_1_PATH = (
    "data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv"
)
REFERENCE_TABLE_V1_1_SHA256 = (
    "7cad0ffa7c9a76a0aa192e24f9fab86b739afd8891ad5dca35624e6a64a39f0e"
)

REFERENCE_CSV_PATH = "data/training/serum/nhanes_serum_pfas_2017_2018.csv"
"""Repo-relative path to the cycle-J governance anchor CSV. Verified
for provenance chain integrity; NOT queried for percentiles at runtime."""

REFERENCE_CSV_SHA256 = (
    "dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f"
)
"""Expected SHA-256 of REFERENCE_CSV_PATH (frozen v1.0 anchor)."""
