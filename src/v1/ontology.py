"""Component 1: Ontology schema loader.

Loads, validates, and exposes the V1 PFOS/PFOA ontology. The
ontology is the single source of truth for what V1 will score,
how it identifies refusals, and what governance scope it claims.

Anything in V1 that needs to know "is this analyte in scope?"
or "what column in the reference holds n-PFOA?" must go through
this module rather than re-parsing the JSON or hardcoding column
names. That keeps the deterministic-replay invariants (same
input + same ontology -> same output) self-evident from a single
file.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


ONTOLOGY_JSON_NAME = "pfos_pfoa_v1.json"
DEFAULT_ONTOLOGY_DIR = Path(__file__).resolve().parent / "data" / "ontology"
DEFAULT_ONTOLOGY_PATH = DEFAULT_ONTOLOGY_DIR / ONTOLOGY_JSON_NAME


@dataclass(frozen=True)
class AnalyteSpec:
    """One scored analyte in the V1 PFOS/PFOA ontology."""

    analyte_id: str
    analyte_label: str
    analyte_family: str
    isomer_class: str
    units: str
    reference_value_column: str
    reference_lod_code_column: str


@dataclass(frozen=True)
class Ontology:
    """Frozen, hashable view of the V1 ontology JSON.

    The `ontology_hash` is the SHA-256 of the raw JSON bytes as
    they live on disk. It is the value that gets folded into the
    provenance manifest and the run_id derivation. Recomputing
    it from the parsed dict would risk drift between disk and
    memory; we hash the bytes once at load time and never let
    that value mutate.
    """

    ontology_id: str
    ontology_version: str
    issued: str
    status: str
    scope: Mapping[str, object]
    intent: str
    required_input_columns: Mapping[str, Mapping[str, object]]
    optional_input_columns: Mapping[str, Mapping[str, object]]
    analytes: tuple
    refusal_codes: tuple
    non_claims: tuple
    raw_bytes: bytes
    ontology_path: Path
    ontology_hash: str

    @property
    def analyte_ids(self) -> tuple:
        """Tuple of scored analyte_id strings, in ontology order."""
        return tuple(a.analyte_id for a in self.analytes)

    def get_analyte(self, analyte_id: str) -> AnalyteSpec | None:
        """Return the AnalyteSpec for analyte_id, or None if not in scope.

        A None return is how the applicability validator detects the
        `analyte_not_in_pfos_pfoa_scope` refusal: anything the
        ontology doesn't carry an entry for is, by construction,
        out of scope.
        """
        for a in self.analytes:
            if a.analyte_id == analyte_id:
                return a
        return None

    def is_in_scope(self, analyte_id: str) -> bool:
        return self.get_analyte(analyte_id) is not None

    @property
    def expected_units(self) -> str:
        return str(self.scope["concentration_units"])

    @property
    def expected_matrix(self) -> str:
        return str(self.scope["matrix"])

    @property
    def expected_source_program(self) -> str:
        return str(self.scope["source_program"])

    @property
    def expected_anchor_csv_path(self) -> str:
        return str(self.scope["anchor_csv_path"])

    @property
    def expected_anchor_csv_sha256(self) -> str:
        return str(self.scope["anchor_csv_sha256"])

    @property
    def expected_reference_table_path(self) -> str:
        return str(self.scope["reference_table_path"])

    @property
    def expected_reference_table_sha256(self) -> str:
        return str(self.scope["reference_table_sha256"])

    @property
    def default_reference_cycle(self) -> str:
        return str(self.scope["default_reference_cycle"])

    @property
    def reference_cycles_available(self) -> tuple:
        raw = self.scope["reference_cycles_available"]
        if not isinstance(raw, list):
            raise OntologyLoadError(
                "Ontology scope.reference_cycles_available must be a list."
            )
        return tuple(str(c) for c in raw)


class OntologyLoadError(RuntimeError):
    """Raised when the on-disk ontology fails structural validation."""


def _sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


_REQUIRED_TOP_KEYS = (
    "ontology_id",
    "ontology_version",
    "issued",
    "status",
    "scope",
    "intent",
    "required_input_columns",
    "optional_input_columns",
    "analytes",
    "refusal_catalog",
    "non_claims",
)

_REQUIRED_SCOPE_KEYS = (
    "matrix",
    "matrix_isolation",
    "analyte_family",
    "isomer_resolution",
    "concentration_units",
    "source_program",
    "anchor_cycle",
    "anchor_governance_directory",
    "anchor_csv_path",
    "anchor_csv_sha256",
    "reference_table_path",
    "reference_table_sha256",
    "default_reference_cycle",
    "reference_cycles_available",
)

_REQUIRED_ANALYTE_KEYS = (
    "analyte_id",
    "analyte_label",
    "analyte_family",
    "isomer_class",
    "units",
    "reference_value_column",
    "reference_lod_code_column",
)


def load_ontology(path: str | Path | None = None) -> Ontology:
    """Read, structurally validate, and hash the V1 ontology.

    Parameters
    ----------
    path
        Optional override for the ontology JSON path. Defaults to
        `src/v1/data/ontology/pfos_pfoa_v1.json`. Tests use this
        override to load a perturbed ontology and verify that the
        ontology_hash changes (the `changed ontology -> changed
        manifest` replay invariant).

    Returns
    -------
    Ontology
        Frozen dataclass; the `ontology_hash` field is the SHA-256
        of the file's raw bytes as read from disk.
    """
    ontology_path = Path(path) if path is not None else DEFAULT_ONTOLOGY_PATH
    if not ontology_path.is_file():
        raise OntologyLoadError(f"Ontology JSON not found: {ontology_path}")

    raw_bytes = ontology_path.read_bytes()
    ontology_hash = _sha256_bytes(raw_bytes)

    try:
        doc = json.loads(raw_bytes.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise OntologyLoadError(
            f"Ontology JSON at {ontology_path} is not valid JSON: {exc}"
        ) from exc

    missing_top = [k for k in _REQUIRED_TOP_KEYS if k not in doc]
    if missing_top:
        raise OntologyLoadError(
            f"Ontology missing required top-level keys: {missing_top}"
        )

    scope = doc["scope"]
    missing_scope = [k for k in _REQUIRED_SCOPE_KEYS if k not in scope]
    if missing_scope:
        raise OntologyLoadError(
            f"Ontology scope missing required keys: {missing_scope}"
        )

    analytes_raw = doc["analytes"]
    if not isinstance(analytes_raw, list) or not analytes_raw:
        raise OntologyLoadError("Ontology must declare at least one analyte.")

    analytes = []
    seen_ids: set[str] = set()
    for i, a in enumerate(analytes_raw):
        missing_an = [k for k in _REQUIRED_ANALYTE_KEYS if k not in a]
        if missing_an:
            raise OntologyLoadError(
                f"Ontology analyte[{i}] missing required keys: {missing_an}"
            )
        aid = a["analyte_id"]
        if aid in seen_ids:
            raise OntologyLoadError(
                f"Ontology declares duplicate analyte_id: {aid!r}"
            )
        seen_ids.add(aid)
        analytes.append(
            AnalyteSpec(
                analyte_id=a["analyte_id"],
                analyte_label=a["analyte_label"],
                analyte_family=a["analyte_family"],
                isomer_class=a["isomer_class"],
                units=a["units"],
                reference_value_column=a["reference_value_column"],
                reference_lod_code_column=a["reference_lod_code_column"],
            )
        )

    refusal_codes = tuple(
        str(r["code"]) for r in doc["refusal_catalog"] if "code" in r
    )
    if not refusal_codes:
        raise OntologyLoadError(
            "Ontology refusal_catalog must declare at least one refusal code."
        )

    return Ontology(
        ontology_id=str(doc["ontology_id"]),
        ontology_version=str(doc["ontology_version"]),
        issued=str(doc["issued"]),
        status=str(doc["status"]),
        scope=dict(scope),
        intent=str(doc["intent"]),
        required_input_columns=dict(doc["required_input_columns"]),
        optional_input_columns=dict(doc["optional_input_columns"]),
        analytes=tuple(analytes),
        refusal_codes=refusal_codes,
        non_claims=tuple(str(s) for s in doc["non_claims"]),
        raw_bytes=raw_bytes,
        ontology_path=ontology_path,
        ontology_hash=ontology_hash,
    )
