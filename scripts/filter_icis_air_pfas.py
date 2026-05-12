"""
Extract PFAS-related rows from EPA ICIS-AIR_POLLUTANTS.csv.

Input layout (canonical):
  PGM_SYS_ID, POLLUTANT_CODE, POLLUTANT_DESC, SRS_ID,
  CHEMICAL_ABSTRACT_SERVICE_NMBR, AIR_POLLUTANT_CLASS_CODE, AIR_POLLUTANT_CLASS_DESC

Match strategy (intentionally conservative):
  1) CAS RN match against a curated PFAS analyte list (dashes stripped, e.g. 1763-23-1 -> 1763231).
  2) POLLUTANT_DESC regex match (same family of patterns used by filter_npdes_dmr_pfas.py).
A row passes if either condition holds. We record match_source per row so reviewers
can audit name-only hits (e.g. trade names, mixtures) separately from CAS-anchored hits.

Outputs:
  data/processed/epa_icis_air/icis_air_pfas_pollutants.csv
    -> filtered rows + matrix governance columns (matrix, source, match_source).
  data/processed/epa_icis_air/icis_air_pfas_facility_rollup.csv
    -> distinct PGM_SYS_ID x analyte counts (handy for the Shiny upload preview).

STRICT scope:
  ICIS-AIR pollutant rows are program-reporting metadata (this facility reports/permits
  this pollutant). They are NOT analytical concentrations. Do not concatenate the
  resulting CSVs with OTM-50 stack-gas measurements, UCMR finished water, NHANES serum,
  or NIST reference rows. Treat as the "air_program_reference" matrix lane and join to
  other lanes only via PGM_SYS_ID / FRS / CAS keys with explicit unit awareness.

Usage:
  python scripts/filter_icis_air_pfas.py
  python scripts/filter_icis_air_pfas.py --input /path/to/ICIS-AIR_POLLUTANTS.csv
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path

PFAS_DESC_RE = re.compile(
    r"(?is)"
    r"(?:perfluoro|polyfluoroalkyl|fluorotelomer|\bPFAS\b|\bADONA\b|HFPO|GenX|\bF-53B\b|"
    r"\bPFOA\b|\bPFOS\b|\bPFNA\b|\bPFHxS\b|\bPFBS\b|\bPFDA\b|\bPFDoA\b|\bPFUnA\b|"
    r"\bPFHxA\b|\bPFHpA\b|\bPFBA\b|\bPFPeA\b|\bPFTrDA\b|\bPFTeDA\b|\bFOSA\b|"
    r"methylperfluor|ethylperfluor|perfluoroct)"
)

# Curated PFAS CAS RN list (acids, sulfonates, replacements, common precursors).
# Stored with dashes for readability; we strip dashes for ICIS-AIR matching.
PFAS_CAS_DASHED = [
    # Carboxylic acids
    "335-67-1",   # PFOA
    "335-76-2",   # PFDA
    "375-22-4",   # PFBA
    "375-85-9",   # PFHpA
    "375-95-1",   # PFNA
    "307-24-4",   # PFHxA
    "307-55-1",   # PFDoDA
    "2058-94-8",  # PFUnDA
    "2706-90-3",  # PFPeA
    "376-06-7",   # PFTeDA
    "72629-94-8", # PFTrDA
    "354-33-6",   # PFPeA (alt registry; kept for safety)
    # Sulfonic acids
    "1763-23-1",  # PFOS
    "355-46-4",   # PFHxS
    "375-73-5",   # PFBS
    "755-38-4",   # PFBS (alt registry)
    "375-92-8",   # PFHpS
    "68259-12-1", # PFNS
    "335-77-3",   # PFDS
    # Sulfonamides / FOSAAs
    "754-91-6",   # FOSA / PFOSA
    "2991-50-6",  # N-EtFOSAA
    "2355-31-9",  # N-MeFOSAA
    "31506-32-8", # N-MeFOSA
    "4151-50-2",  # N-EtFOSA
    # Fluorotelomer sulfonates
    "27619-97-2", # 6:2 FTS
    "39108-34-4", # 8:2 FTS
    "757124-72-4",# 4:2 FTS
    # Replacements / GenX / ADONA / F-53B
    "13252-13-6", # HFPO-DA (GenX free acid)
    "62037-80-3", # HFPO-DA ammonium salt
    "919005-14-4",# ADONA
    "756426-58-1",# 9Cl-PF3ONS (major F-53B)
    "763051-92-9",# 11Cl-PF3OUdS (minor F-53B)
    "29420-49-3", # PFBS potassium salt
    "2795-39-3",  # PFOS potassium salt
    "335-93-3",   # PFOS sodium salt
    "4151-50-2",  # NEtFOSA (duplicate-safe; dedup below)
    "2991-51-7",  # FOSAA acid (PFOSAA)
]

OUT_REL = Path("data") / "processed" / "epa_icis_air"
DEFAULT_INPUT_REL = Path("data") / "raw" / "epa_icis_air" / "ICIS-AIR_POLLUTANTS.csv"


def _project_root_from_script() -> Path:
    return Path(__file__).resolve().parent.parent


def _normalize_cas(value: str) -> str:
    return "".join(ch for ch in (value or "") if ch.isdigit())


def _build_cas_set() -> set[str]:
    return {_normalize_cas(c) for c in PFAS_CAS_DASHED if _normalize_cas(c)}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--input",
        type=Path,
        default=None,
        help="ICIS-AIR_POLLUTANTS.csv path (default: <repo>/data/raw/epa_icis_air/ICIS-AIR_POLLUTANTS.csv)",
    )
    p.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Output folder (default: <repo>/data/processed/epa_icis_air/)",
    )
    p.add_argument(
        "--encoding",
        type=str,
        default="latin-1",
        help="Input encoding (default latin-1 for EPA bulk files)",
    )
    p.add_argument(
        "--max-rows",
        type=int,
        default=None,
        help="Stop after reading N input rows (debug / smoke).",
    )
    return p.parse_args()


def _open_input(path: Path, encoding: str):
    return path.open("r", encoding=encoding, newline="")


def main() -> int:
    args = parse_args()
    root = _project_root_from_script()
    input_path = (args.input or (root / DEFAULT_INPUT_REL)).resolve()
    out_dir = (args.out_dir or (root / OUT_REL)).resolve()

    if not input_path.is_file():
        print(
            f"ERROR: input not found: {input_path}\n"
            f"Hint: run download_epa_icis_air.ps1 or pass --input.",
            file=sys.stderr,
        )
        return 2

    out_dir.mkdir(parents=True, exist_ok=True)
    pfas_csv = out_dir / "icis_air_pfas_pollutants.csv"
    rollup_csv = out_dir / "icis_air_pfas_facility_rollup.csv"

    cas_set = _build_cas_set()

    out_header = [
        "pgm_sys_id",
        "pollutant_code",
        "pollutant_desc",
        "srs_id",
        "cas_rn_raw",
        "cas_rn_dashed",
        "air_pollutant_class_code",
        "air_pollutant_class_desc",
        "match_source",      # cas | desc | cas+desc
        "pfas_class_note",   # governance caveat (e.g. GHG-aggregate PFC code)
        "matrix",            # air_program_reference
        "source",            # EPA_ICIS_AIR
    ]

    # Governance caveats keyed by normalized CAS RN.
    # 308069-13-8 is EPA's aggregate "Perfluorocarbons" identifier used for fluorinated
    # GHGs (CF4, C2F6, C3F8, c-C4F8, etc.). It is NOT a drinking-water-class PFAS
    # analyte and should not be conflated with PFOA/PFOS/PFNA-style targets.
    CAS_NOTE = {
        "308069138": (
            "EPA aggregate 'Perfluorocarbons' identifier (fluorinated GHGs such as CF4, "
            "C2F6, C3F8). NOT a drinking-water-class PFAS analyte; do not conflate with "
            "PFOA/PFOS/PFNA targets."
        ),
    }

    rows_in = 0
    rows_kept = 0
    cas_only = 0
    desc_only = 0
    both = 0
    facility_counter: Counter[tuple[str, str, str]] = Counter()
    # facility_counter key = (pgm_sys_id, pollutant_code, pollutant_desc)

    with _open_input(input_path, args.encoding) as fin, pfas_csv.open(
        "w", encoding="utf-8", newline=""
    ) as fout:
        reader = csv.DictReader(fin)
        writer = csv.writer(fout)
        writer.writerow(out_header)

        required_cols = {
            "PGM_SYS_ID",
            "POLLUTANT_CODE",
            "POLLUTANT_DESC",
            "SRS_ID",
            "CHEMICAL_ABSTRACT_SERVICE_NMBR",
            "AIR_POLLUTANT_CLASS_CODE",
            "AIR_POLLUTANT_CLASS_DESC",
        }
        missing = required_cols - set(reader.fieldnames or [])
        if missing:
            print(
                f"ERROR: input is missing required columns: {sorted(missing)}\n"
                f"Got: {reader.fieldnames}",
                file=sys.stderr,
            )
            return 3

        for row in reader:
            rows_in += 1
            if args.max_rows is not None and rows_in > args.max_rows:
                break

            cas_raw = (row.get("CHEMICAL_ABSTRACT_SERVICE_NMBR") or "").strip()
            cas_norm = _normalize_cas(cas_raw)
            desc = (row.get("POLLUTANT_DESC") or "").strip()

            cas_hit = bool(cas_norm) and cas_norm in cas_set
            desc_hit = bool(desc) and bool(PFAS_DESC_RE.search(desc))

            if not (cas_hit or desc_hit):
                continue

            if cas_hit and desc_hit:
                match_source = "cas+desc"
                both += 1
            elif cas_hit:
                match_source = "cas"
                cas_only += 1
            else:
                match_source = "desc"
                desc_only += 1

            pgm_sys_id = (row.get("PGM_SYS_ID") or "").strip()
            pollutant_code = (row.get("POLLUTANT_CODE") or "").strip()
            srs_id = (row.get("SRS_ID") or "").strip()
            air_class_code = (row.get("AIR_POLLUTANT_CLASS_CODE") or "").strip()
            air_class_desc = (row.get("AIR_POLLUTANT_CLASS_DESC") or "").strip()

            # Reconstruct dashed CAS RN best-effort: most US CAS RNs are XX...X-XX-X.
            cas_dashed = ""
            if cas_norm and len(cas_norm) >= 4:
                cas_dashed = f"{cas_norm[:-3]}-{cas_norm[-3:-1]}-{cas_norm[-1]}"

            pfas_class_note = CAS_NOTE.get(cas_norm, "")
            writer.writerow(
                [
                    pgm_sys_id,
                    pollutant_code,
                    desc,
                    srs_id,
                    cas_raw,
                    cas_dashed,
                    air_class_code,
                    air_class_desc,
                    match_source,
                    pfas_class_note,
                    "air_program_reference",
                    "EPA_ICIS_AIR",
                ]
            )
            rows_kept += 1
            facility_counter[(pgm_sys_id, pollutant_code, desc)] += 1

    with rollup_csv.open("w", encoding="utf-8", newline="") as fout:
        writer = csv.writer(fout)
        writer.writerow(
            [
                "pgm_sys_id",
                "pollutant_code",
                "pollutant_desc",
                "row_count",
                "matrix",
                "source",
            ]
        )
        for (pgm, code, desc), n in facility_counter.most_common():
            writer.writerow(
                [pgm, code, desc, n, "air_program_reference", "EPA_ICIS_AIR"]
            )

    print(
        f"filter_icis_air_pfas: rows_in={rows_in} rows_kept={rows_kept} "
        f"cas_only={cas_only} desc_only={desc_only} both={both} "
        f"distinct_facility_x_analyte={len(facility_counter)}",
        file=sys.stderr,
    )
    print(f"  rows out:    {pfas_csv}", file=sys.stderr)
    print(f"  rollup out:  {rollup_csv}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
