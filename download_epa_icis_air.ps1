# Download EPA ECHO ICIS-AIR bulk extract useful for PFAS-oriented facility / source ML.
#
# Reality check (aligns with EPA documentation on ICIS-AIR):
# - ICIS-AIR_POLLUTANTS.csv: facility-level pollutant program reporting (PGM_SYS_ID,
#   POLLUTANT_CODE, POLLUTANT_DESC, SRS_ID, CAS_RN, AIR_POLLUTANT_CLASS_*). It is NOT
#   a stack measurement file. Rows are "this facility reports/permits this pollutant
#   under the air program" rows, not ng/m^3 concentrations.
# - ICIS-AIR_FACILITIES.csv: facility identity and location.
# - ICIS-AIR_STACK_TESTS.csv: stack-test events (counts/dates, not analyte values).
# - ICIS-AIR_PROGRAMS / SUBPARTS / TITLEV_CERTS / *_ACTIONS / VIOLATION_HISTORY:
#   regulatory context tables.
#
# Canonical list + URL: https://echo.epa.gov/tools/data-downloads (ICIS-AIR section).
#
# STRICT: ICIS-AIR pollutant rows are program-reporting metadata, not analytical
# concentrations. Do not concatenate with OTM-50 stack-gas measurements, UCMR finished
# water, NHANES serum, or NIST reference rows. Treat as the "air program reference"
# lane and join to other matrices only via PGM_SYS_ID / FRS / CAS keys.

param(
    [switch] $Force,
    [switch] $SkipUnzip
)

$ErrorActionPreference = "Stop"

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$projectRoot = $PSScriptRoot
if ($env:EPA_ICIS_AIR_PROJECT_ROOT) {
    $projectRoot = $env:EPA_ICIS_AIR_PROJECT_ROOT
}

$outDir = Join-Path $projectRoot "data\raw\epa_icis_air"
if ($env:EPA_ICIS_AIR_OUTDIR) {
    $outDir = $env:EPA_ICIS_AIR_OUTDIR
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$zipUrl = "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
$zipPath = Join-Path $outDir "ICIS-AIR_downloads.zip"

if ((Test-Path -LiteralPath $zipPath) -and (-not $Force)) {
    Write-Host "Skip (exists): ICIS-AIR_downloads.zip"
} else {
    Write-Host "Downloading ICIS-AIR_downloads.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
}

if (-not $SkipUnzip) {
    Write-Host "Expanding ICIS-AIR_downloads.zip"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $outDir -Force
}

Write-Host ""
Write-Host "Done. Files saved to $outDir"
Write-Host "Matrix lane: air_program_reference (EPA ICIS-AIR program reporting)."
Write-Host "Next: python scripts/filter_icis_air_pfas.py --input '$outDir\ICIS-AIR_POLLUTANTS.csv'"
