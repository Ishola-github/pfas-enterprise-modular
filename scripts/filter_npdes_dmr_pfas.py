"""
Extract PFAS-related rows from EPA ICIS-NPDES fiscal-year DMR bulk CSVs.

Reads ``npdes_dmrs_fy{YYYY}.zip`` in place (no full unzip) and streams chunks.
Matches rows by:
  - PARAMETER_DESC against a PFAS-oriented regex, and/or
  - PARAMETER_CODE from REF_Parameter.csv rows whose descriptions match the same regex.

DMR layout: https://echo.epa.gov/tools/data-downloads/icis-npdes-dmr-summary

Example (after download_epa_icis_npdes_ml.ps1):
  python scripts/filter_npdes_dmr_pfas.py --fiscal-year 2024 --max-chunks 5
  python scripts/filter_npdes_dmr_pfas.py --fiscal-year 2024
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

import pandas as pd

# Non-capturing groups only (pandas ``str.contains`` warns on capturing groups).
PFAS_PARAM_DESC_RE = re.compile(
    r"(?is)"
    r"(?:perfluoro|polyfluoroalkyl|fluorotelomer|\bPFAS\b|\bADONA\b|HFPO|GenX|\bF-53B\b|Sulfluramid|"
    r"\bPFOA\b|\bPFOS\b|\bPFNA\b|\bPFHxS\b|\bPFBS\b|\bPFDA\b|\bPFDoA\b|\bPFUnA\b|\bPFHxA\b|"
    r"methylperfluor|ethylperfluor|perfluoroct)"
)


def _default_data_root(script_path: Path) -> Path:
    return script_path.resolve().parent.parent / "data" / "raw" / "epa_icis_npdes"


def _default_out_csv(script_path: Path, fiscal_year: str) -> Path:
    return (
        script_path.resolve().parent.parent
        / "data"
        / "processed"
        / f"npdes_dmr_pfas_fy{fiscal_year}.csv"
    )


def _find_dmr_member(z: zipfile.ZipFile) -> str:
    csvs = [
        n
        for n in z.namelist()
        if n.lower().endswith(".csv") and "dmr" in Path(n).stem.lower()
    ]
    if not csvs:
        raise ValueError(f"No DMR CSV found in zip; members={z.namelist()[:20]}...")
    if len(csvs) > 1:
        csvs.sort(key=lambda x: ("npdes_dmr" not in Path(x).stem.lower(), len(x)))
    return csvs[0]


def load_pfas_parameter_codes(ref_parameter_csv: Path) -> set[str]:
    ref = pd.read_csv(ref_parameter_csv, dtype=str, low_memory=False)
    if "PARAMETER_CODE" not in ref.columns or "PARAMETER_DESC" not in ref.columns:
        raise ValueError(f"Unexpected REF_Parameter columns: {list(ref.columns)}")
    desc = ref["PARAMETER_DESC"].fillna("").astype(str)
    mask = desc.str.contains(PFAS_PARAM_DESC_RE, na=False)
    codes = ref.loc[mask, "PARAMETER_CODE"].astype(str).str.strip()
    return set(codes)


def filter_chunk(chunk: pd.DataFrame, ref_codes: set[str]) -> pd.DataFrame:
    if "PARAMETER_CODE" not in chunk.columns:
        raise ValueError(f"DMR missing PARAMETER_CODE; columns={list(chunk.columns)[:40]}...")
    code = chunk["PARAMETER_CODE"].astype(str).str.strip()
    desc = (
        chunk["PARAMETER_DESC"].fillna("").astype(str)
        if "PARAMETER_DESC" in chunk.columns
        else pd.Series("", index=chunk.index)
    )
    mask = code.isin(ref_codes) | desc.str.contains(PFAS_PARAM_DESC_RE, na=False)
    return chunk.loc[mask]


def stream_dmr_from_zip(
    zip_path: Path,
    ref_codes: set[str],
    out_csv: Path,
    chunksize: int,
    encoding: str,
    max_chunks: int | None,
) -> tuple[int, int]:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    header_written = False
    rows_matched = 0
    chunks_read = 0

    with zipfile.ZipFile(zip_path) as z:
        member = _find_dmr_member(z)
        reader = pd.read_csv(
            z.open(member),
            chunksize=chunksize,
            encoding=encoding,
            low_memory=False,
        )
        for chunk in reader:
            chunks_read += 1
            part = filter_chunk(chunk, ref_codes)
            if not part.empty:
                rows_matched += len(part)
                part.to_csv(out_csv, mode="a", index=False, header=not header_written)
                header_written = True
            if max_chunks is not None and chunks_read >= max_chunks:
                break

    return rows_matched, chunks_read


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--fiscal-year",
        type=str,
        default="2024",
        help="Federal fiscal year on npdes_dmrs_fy{year}.zip (default: 2024)",
    )
    p.add_argument(
        "--data-root",
        type=Path,
        default=None,
        help="Folder with npdes_dmrs_*.zip and ref_tables/ (default: <repo>/data/raw/epa_icis_npdes)",
    )
    p.add_argument(
        "--zip",
        type=Path,
        default=None,
        help="Explicit path to npdes_dmrs_fy####.zip",
    )
    p.add_argument(
        "--ref-parameter",
        type=Path,
        default=None,
        help="REF_Parameter.csv (default: <data-root>/ref_tables/REF_Parameter.csv)",
    )
    p.add_argument(
        "--out-csv",
        type=Path,
        default=None,
        help="Output CSV (default: <repo>/data/processed/npdes_dmr_pfas_fy{year}.csv)",
    )
    p.add_argument("--chunksize", type=int, default=200_000)
    p.add_argument(
        "--encoding",
        type=str,
        default="latin-1",
        help="DMR CSV encoding (default latin-1 for odd EPA byte sequences)",
    )
    p.add_argument(
        "--max-chunks",
        type=int,
        default=None,
        help="Stop after N raw DMR chunks (debug / smoke)",
    )
    return p.parse_args()


def main() -> None:
    script_path = Path(__file__)
    args = parse_args()
    data_root = args.data_root or _default_data_root(script_path)
    ref_path = args.ref_parameter or (data_root / "ref_tables" / "REF_Parameter.csv")
    zip_path = args.zip or (data_root / f"npdes_dmrs_fy{args.fiscal_year}.zip")
    out_csv = args.out_csv or _default_out_csv(script_path, args.fiscal_year)

    if not ref_path.is_file():
        raise SystemExit(
            f"Missing {ref_path}. Run download_epa_icis_npdes_ml.ps1 -SkipDmr first "
            "or pass --ref-parameter."
        )
    if not zip_path.is_file():
        raise SystemExit(
            f"Missing {zip_path}. Run download_epa_icis_npdes_ml.ps1 or pass --zip."
        )

    ref_codes = load_pfas_parameter_codes(ref_path)
    rows_matched, chunks_read = stream_dmr_from_zip(
        zip_path,
        ref_codes,
        out_csv,
        args.chunksize,
        args.encoding,
        args.max_chunks,
    )
    print(
        f"filter_npdes_dmr_pfas: ref_codes={len(ref_codes)} chunks_read={chunks_read} "
        f"rows_matched={rows_matched} out={out_csv}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
