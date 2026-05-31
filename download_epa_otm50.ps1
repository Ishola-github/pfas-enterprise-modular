# Download EPA OTM-50 PFAS air-emissions dataset (Shields et al., 2024 / 2025).
#
# Source: EPA Office of Research and Development (ORD), DOI 10.23719/1531897.
# Data.gov landing page:
#   https://catalog.data.gov/dataset/otm-50-data-from-air-pollution-controls-at-a-fluoropolymer-manufacturer-2024
# Associated publication:
#   Shields, E., Roberson, W., Ryan, J., Jackson, S. (2025). The Use of Air Pollution Controls
#   to Reduce the Gas-phase Emissions of Per- and Polyfluoroalkyl Substances from a
#   Fluoropolymer Manufacturing Facility. ES&T Letters.
#   https://pubs.acs.org/doi/10.1021/acs.estlett.5c00402
# License: https://pasteur.epa.gov/license/sciencehub-license.html
#
# Reality check (aligns with EPA OTM-50 scope):
# - This is a STACK / process-controls air-emissions dataset from one fluoropolymer manufacturer.
#   It is industrial source-emission data, not ambient air, not drinking water, not biosolids,
#   and not human biomonitoring. Treat the matrix as "air_emissions" / "stack_gas".
# - Files are XLSX workbooks with per-run measurement tables. Convert with openpyxl / readxl
#   downstream; do not auto-merge their analyte rows with UCMR (water) or NHANES (serum) data.
#
# STRICT: keep this matrix in its own lane. UCMR, NHANES, biosolids, AFFF, methanol, and
# air-emissions PFAS rows must not be concatenated into a single generalized PFAS table.

param(
    [switch] $Force
)

$ErrorActionPreference = "Stop"

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$projectRoot = $PSScriptRoot
if ($env:EPA_OTM50_PROJECT_ROOT) {
    $projectRoot = $env:EPA_OTM50_PROJECT_ROOT
}

$outDir = Join-Path $projectRoot "data\external\epa_otm50"
if ($env:EPA_OTM50_OUTDIR) {
    $outDir = $env:EPA_OTM50_OUTDIR
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$downloads = @(
    @{
        Name = "FW_TO_OTM-50data_2023.xlsx"
        Url  = "https://pasteur.epa.gov/uploads/10.23719/1531897/FW_TO_OTM-50data_2023.xlsx"
    },
    @{
        Name = "FW_VEN_OTM-50data_2023.xlsx"
        Url  = "https://pasteur.epa.gov/uploads/10.23719/1531897/FW_VEN_OTM-50data_2023.xlsx"
    },
    @{
        Name = "FW_VES_OTM-50data_2024.xlsx"
        Url  = "https://pasteur.epa.gov/uploads/10.23719/1531897/FW_VES_OTM-50data_2024.xlsx"
    }
)

foreach ($d in $downloads) {
    $out = Join-Path $outDir $d.Name
    if ((Test-Path -LiteralPath $out) -and (-not $Force)) {
        Write-Host "Skip (exists): $($d.Name)"
        continue
    }
    Write-Host "Downloading $($d.Name)"
    Invoke-WebRequest -Uri $d.Url -OutFile $out -UseBasicParsing
}

Write-Host ""
Write-Host "Done. Files saved to $outDir"
Write-Host "Matrix lane: air_emissions / stack_gas (industrial source) - do not merge with water or serum data."
Write-Host "After download, recompute SHA-256 and add an air_emissions row to data/reference/registry/reference_registry.csv."
