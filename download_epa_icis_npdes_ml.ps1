# Download EPA ECHO ICIS-NPDES extracts useful for PFAS-oriented facility / monitoring ML.
#
# Reality check (aligns with EPA documentation on ECHO):
# - Biosolids ZIP: facility/compliance metadata for the biosolids universe — not nationwide PFAS
#   sludge analytical concentrations. Still valuable joined to occurrence or DMR signals.
# - DMR fiscal-year ZIPs: discharge monitoring values, parameter codes, periods, outfalls linkage.
# - National permit limits ZIP: limit values, parameter codes, units — exceedance / monitoring features.
# - Outfalls ZIP: coordinates and facility linkage for geospatial models.
# - Reference CSVs: map PARAMETER_CODE and related DMR/limit fields.
#
# Canonical list + URLs: https://echo.epa.gov/tools/data-downloads
#
# STRICT: DMR rows are effluent/discharge monitoring — do not treat as human biomarker data.
# Join keys and interpretation differ from NHANES serum or UCMR finished-water samples.

param(
    [string[]] $DmrFiscalYears = @("2024", "2025"),
    [switch] $IncludeNationalPermitLimitsZip,
    [switch] $SkipBiosolids,
    [switch] $SkipOutfalls,
    [switch] $SkipReferenceTables,
    [switch] $SkipDmr
)

$ErrorActionPreference = "Stop"

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$projectRoot = $PSScriptRoot
if ($env:EPA_ICIS_NPDES_PROJECT_ROOT) {
    $projectRoot = $env:EPA_ICIS_NPDES_PROJECT_ROOT
}

$outDir = Join-Path $projectRoot "data\raw\epa_icis_npdes"
if ($env:EPA_ICIS_NPDES_OUTDIR) {
    $outDir = $env:EPA_ICIS_NPDES_OUTDIR
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$refDir = Join-Path $outDir "ref_tables"
New-Item -ItemType Directory -Force -Path $refDir | Out-Null

function Save-Url {
    param(
        [string] $Url,
        [string] $DestinationPath
    )
    if (Test-Path -LiteralPath $DestinationPath) {
        Write-Host "Skip (exists): $(Split-Path -Leaf $DestinationPath)"
        return
    }
    Write-Host "Downloading $(Split-Path -Leaf $DestinationPath)"
    Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing
}

$downloads = [System.Collections.Generic.List[hashtable]]::new()

if (-not $SkipBiosolids) {
    $downloads.Add(@{
        Path = Join-Path $outDir "npdes_biosolids_downloads.zip"
        Url  = "https://echo.epa.gov/files/echodownloads/npdes_biosolids_downloads.zip"
    })
}

if (-not $SkipOutfalls) {
    $downloads.Add(@{
        Path = Join-Path $outDir "npdes_outfalls_layer.zip"
        Url  = "https://echo.epa.gov/files/echodownloads/npdes_outfalls_layer.zip"
    })
}

if ($IncludeNationalPermitLimitsZip) {
    $downloads.Add(@{
        Path = Join-Path $outDir "npdes_limits.zip"
        Url  = "https://echo.epa.gov/files/echodownloads/npdes_limits.zip"
    })
}

if (-not $SkipDmr) {
    foreach ($fy in $DmrFiscalYears) {
        $downloads.Add(@{
            Path = Join-Path $outDir "npdes_dmrs_fy$fy.zip"
            Url  = "https://echo.epa.gov/files/echodownloads/npdes_dmrs_fy$fy.zip"
        })
    }
}

if (-not $SkipReferenceTables) {
    $downloads.Add(@{ Path = Join-Path $refDir "REF_Parameter.csv"
            Url       = "https://echo.epa.gov/system/files/REF_Parameter.csv" })
    $downloads.Add(@{ Path = Join-Path $refDir "REF_STATISTICAL_BASE.csv"
            Url       = "https://echo.epa.gov/files/echodownloads/ref_tables/REF_STATISTICAL_BASE.csv" })
    $downloads.Add(@{ Path = Join-Path $refDir "REF_FREQUENCY_OF_ANALYSIS.csv"
            Url       = "https://echo.epa.gov/system/files/REF_FREQUENCY_OF_ANALYSIS.csv" })
    $downloads.Add(@{ Path = Join-Path $refDir "REF_SAMPLE_TYPE_0.csv"
            Url       = "https://echo.epa.gov/system/files/REF_SAMPLE_TYPE_0.csv" })
}

foreach ($d in $downloads) {
    Save-Url -Url $d.Url -DestinationPath $d.Path
}

Write-Host "Done. Files under $outDir"
Write-Host "Documentation: https://echo.epa.gov/tools/data-downloads"
Write-Host "National permit limits (~459 MB) omitted unless -IncludeNationalPermitLimitsZip."
