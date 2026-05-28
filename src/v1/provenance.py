"""Component 4: Provenance logger.

Records the bit-identical chain of custody for a single V1 run:

    input_hash       SHA-256 of the input CSV bytes.
    reference_hash   SHA-256 of the weighted reference table
                     (must equal the documented table hash).
    ontology_hash    SHA-256 of the ontology JSON bytes.
    code_version     src.v1.__version__ (independent of git).
    git_revision     git rev-parse HEAD if available, else None.
    ontology_version "ontology_version" string from the ontology
                     JSON (independent of code_version).
    timestamp        ISO-8601 UTC; METADATA ONLY. Excluded from
                     run_id derivation so two identical runs at
                     different times produce the same run_id.
    run_id           SHA-256 over a canonical join of
                     (input_hash, reference_hash, ontology_hash,
                     code_version, ontology_version), truncated
                     to 16 hex chars. Deterministic.
    output_hash      SHA-256 of the bytes that would be written
                     to the report CSV. The report generator
                     computes this and the logger stores it.

The deterministic-replay invariant the user enumerated as
replay test #1 ("same input -> same output hash") is implemented
exactly here: given the same four content hashes and the same
code/ontology versions, run_id is deterministic. The report
generator emits CSV bytes that are themselves deterministic
(no timestamps embedded in the CSV body), so output_hash is
also deterministic.

Replay test #2 ("changed ontology -> changed manifest") follows
because editing the ontology JSON changes its SHA-256, which
changes ontology_hash, which changes run_id, which changes
output_hash.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(path: str | Path) -> str:
    p = Path(path)
    return sha256_bytes(p.read_bytes())


def _git_rev_parse_head(repo_root: Path) -> str | None:
    """Best-effort git SHA. Returns None if git is unavailable
    or this isn't a git checkout. The run still proceeds; only
    the optional `git_revision` field is omitted.
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_root),
            check=False,
            capture_output=True,
            timeout=5,
            text=True,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    sha = result.stdout.strip()
    return sha if sha and all(c in "0123456789abcdef" for c in sha.lower()) else None


@dataclass(frozen=True)
class ProvenanceRecord:
    """Bit-identical chain of custody for one V1 run.

    Designed to round-trip through JSON via `to_dict()` /
    `to_json_bytes()`; the manifest written next to the report
    CSV is exactly what `to_json_bytes(sort_keys=True)`
    produces.
    """

    input_csv_path: str
    input_csv_sha256: str
    input_csv_n_bytes: int

    reference_table_path: str
    reference_table_sha256: str
    reference_table_n_bytes: int
    reference_table_documented_sha256: str

    ontology_path: str
    ontology_sha256: str
    ontology_version: str

    code_version: str
    git_revision: str | None
    python_implementation: str

    timestamp_utc: str
    run_id: str

    anchor_csv_path: str | None = None
    anchor_csv_sha256: str | None = None
    anchor_csv_documented_sha256: str | None = None
    output_csv_sha256: str | None = None
    output_csv_n_bytes: int | None = None

    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        # Drop None-valued optional fields so the manifest stays
        # compact and so a manifest written before/after the
        # report differs only by populated output_* fields, not
        # by None vs absent keys.
        return {k: v for k, v in d.items() if v is not None}

    def to_json_bytes(self, *, sort_keys: bool = True) -> bytes:
        return json.dumps(
            self.to_dict(),
            sort_keys=sort_keys,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")


def derive_run_id(
    *,
    input_hash: str,
    reference_hash: str,
    ontology_hash: str,
    code_version: str,
    ontology_version: str,
) -> str:
    """Compute the deterministic run_id.

    The join order and separator are pinned: any change here is
    a breaking change to the replay contract and must be
    accompanied by a code_version bump.
    """
    joined = "|".join(
        [
            "input=" + input_hash,
            "reference=" + reference_hash,
            "ontology=" + ontology_hash,
            "code_version=" + code_version,
            "ontology_version=" + ontology_version,
        ]
    )
    return sha256_bytes(joined.encode("utf-8"))[:16]


def build_provenance(
    *,
    input_csv_path: str | Path,
    reference_table_path: str | Path,
    ontology_path: str | Path,
    reference_table_documented_sha256: str,
    code_version: str,
    ontology_version: str,
    anchor_csv_path: str | Path | None = None,
    anchor_csv_documented_sha256: str | None = None,
    repo_root: str | Path | None = None,
    extra: dict[str, Any] | None = None,
) -> ProvenanceRecord:
    """Build a fully populated ProvenanceRecord for the current run.

    The output_csv_sha256 / output_csv_n_bytes fields are left
    None and filled in by the report generator via
    ``stamp_output(record, csv_bytes)``. ``run_id`` is derived
    from the input hash, the **weighted reference table** hash,
    the ontology hash, and the version strings — not from the
    anchor CSV (which is recorded separately for chain-of-custody).
    """
    input_path = Path(input_csv_path)
    reference_path = Path(reference_table_path)
    ontology_full_path = Path(ontology_path)

    input_bytes = input_path.read_bytes()
    reference_bytes = reference_path.read_bytes()
    ontology_bytes = ontology_full_path.read_bytes()

    input_hash = sha256_bytes(input_bytes)
    reference_hash = sha256_bytes(reference_bytes)
    ontology_hash = sha256_bytes(ontology_bytes)

    if reference_hash.lower() != reference_table_documented_sha256.lower():
        raise RuntimeError(
            "Reference table SHA-256 disagreement: on-disk "
            f"{reference_hash} vs documented "
            f"{reference_table_documented_sha256}. Refusing to "
            "log provenance for a drifted reference."
        )

    anchor_path: Path | None = None
    anchor_hash: str | None = None
    if anchor_csv_path is not None:
        anchor_path = Path(anchor_csv_path)
        anchor_bytes = anchor_path.read_bytes()
        anchor_hash = sha256_bytes(anchor_bytes)
        if anchor_csv_documented_sha256 is not None:
            if anchor_hash.lower() != anchor_csv_documented_sha256.lower():
                raise RuntimeError(
                    "Anchor CSV SHA-256 disagreement: on-disk "
                    f"{anchor_hash} vs documented "
                    f"{anchor_csv_documented_sha256}."
                )

    run_id = derive_run_id(
        input_hash=input_hash,
        reference_hash=reference_hash,
        ontology_hash=ontology_hash,
        code_version=code_version,
        ontology_version=ontology_version,
    )

    git_sha: str | None = None
    if repo_root is not None:
        git_sha = _git_rev_parse_head(Path(repo_root))

    timestamp_utc = (
        datetime.now(tz=timezone.utc).replace(microsecond=0).isoformat()
    )

    import platform

    return ProvenanceRecord(
        input_csv_path=str(input_path),
        input_csv_sha256=input_hash,
        input_csv_n_bytes=len(input_bytes),
        reference_table_path=str(reference_path),
        reference_table_sha256=reference_hash,
        reference_table_n_bytes=len(reference_bytes),
        reference_table_documented_sha256=reference_table_documented_sha256,
        anchor_csv_path=str(anchor_path) if anchor_path is not None else None,
        anchor_csv_sha256=anchor_hash,
        anchor_csv_documented_sha256=anchor_csv_documented_sha256,
        ontology_path=str(ontology_full_path),
        ontology_sha256=ontology_hash,
        ontology_version=ontology_version,
        code_version=code_version,
        git_revision=git_sha,
        python_implementation=(
            f"{platform.python_implementation()} {platform.python_version()}"
        ),
        timestamp_utc=timestamp_utc,
        run_id=run_id,
        output_csv_sha256=None,
        output_csv_n_bytes=None,
        extra=extra or {},
    )


def stamp_output(
    record: ProvenanceRecord,
    output_csv_bytes: bytes,
) -> ProvenanceRecord:
    """Return a copy of `record` with output_csv_sha256 / n_bytes filled in.

    The frozen dataclass is intentionally immutable; callers
    receive a new record and write its JSON to disk alongside
    the report CSV.
    """
    return ProvenanceRecord(
        **{
            **{k: getattr(record, k) for k in record.__dataclass_fields__ if k not in {"output_csv_sha256", "output_csv_n_bytes"}},
            "output_csv_sha256": sha256_bytes(output_csv_bytes),
            "output_csv_n_bytes": len(output_csv_bytes),
        }
    )
