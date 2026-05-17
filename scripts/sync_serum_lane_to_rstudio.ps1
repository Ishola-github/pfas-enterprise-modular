# Sync serum lane + V1 bundle from pfas-toxicology into PFAS_on_R_Studio.
#
# Usage (from pfas-toxicology repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\sync_serum_lane_to_rstudio.ps1
#
# Default destination:
#   C:\Users\techj\OneDrive\Desktop\python_work\PFAS_on_R_Studio

$ErrorActionPreference = "Stop"
$Src = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "LatestPFAS.R")) {
    $Src = Split-Path $PSScriptRoot -Parent
}
$Dst = "C:\Users\techj\OneDrive\Desktop\python_work\PFAS_on_R_Studio"

Write-Host "Source: $Src"
Write-Host "Dest:   $Dst"

function Ensure-Dir($p) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

Ensure-Dir $Dst
Ensure-Dir (Join-Path $Dst "scripts")
Ensure-Dir (Join-Path $Dst "src")
Ensure-Dir (Join-Path $Dst "data\v1\templates")
Ensure-Dir (Join-Path $Dst "data\v1\fixtures")
Ensure-Dir (Join-Path $Dst "data\reference_tables")
Ensure-Dir (Join-Path $Dst "data\training\serum")
Ensure-Dir (Join-Path $Dst "data\raw\nhanes")
Ensure-Dir (Join-Path $Dst "data\config")
Ensure-Dir (Join-Path $Dst "validation\serum_v1")
Ensure-Dir (Join-Path $Dst "data\external\nist_pfas")
Ensure-Dir (Join-Path $Dst "data\reference\nist\srm1957")

# Python V1 package (remove dest first — Copy-Item into existing dir nests src\v1\v1)
$v1Dst = Join-Path $Dst "src\v1"
if (Test-Path $v1Dst) {
    Remove-Item -Recurse -Force $v1Dst
}
Copy-Item -Recurse -Force (Join-Path $Src "src\v1") $v1Dst
if (Test-Path (Join-Path $Src "src\__init__.py")) {
    Copy-Item -Force (Join-Path $Src "src\__init__.py") (Join-Path $Dst "src\__init__.py")
}

# Scripts
@(
    "run_v1_contextualization.R",
    "run_matrix_pipeline.py",
    "smoke_v1_shiny_integration.R",
    "fetch_nhanes_pfas_demo.py",
    "convert_legacy_serum_batch_to_v1.py",
    "enrich_v1_input_demographics.py",
    "build_v1_governed_input_from_nhanes.py",
    "build_nhanes_weighted_reference_tables_v1_1.py",
    "run_v2_contextualization.R",
    "smoke_v2_shiny_integration.R",
    "confirm_nhanes_downloads.ps1",
    "download_nhanes_pfas.ps1"
) | ForEach-Object {
    $f = Join-Path $Src "scripts\$_"
    if (Test-Path $f) { Copy-Item -Force $f (Join-Path $Dst "scripts\$_") }
}

# Governance + data
Copy-Item -Recurse -Force (Join-Path $Src "validation\serum_v1") (Join-Path $Dst "validation\serum_v1")
if (Test-Path (Join-Path $Src "validation\serum_v2")) {
    Copy-Item -Recurse -Force (Join-Path $Src "validation\serum_v2") (Join-Path $Dst "validation\serum_v2")
}
$v2Dst = Join-Path $Dst "src\v2"
if (Test-Path (Join-Path $Src "src\v2")) {
    if (Test-Path $v2Dst) { Remove-Item -Recurse -Force $v2Dst }
    Copy-Item -Recurse -Force (Join-Path $Src "src\v2") $v2Dst
}
$v1DataDst = Join-Path $Dst "data\v1"
if (Test-Path $v1DataDst) {
    Get-ChildItem $v1DataDst -Exclude "outputs" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
Copy-Item -Recurse -Force (Join-Path $Src "data\v1\templates") (Join-Path $Dst "data\v1\templates")
Copy-Item -Recurse -Force (Join-Path $Src "data\v1\fixtures") (Join-Path $Dst "data\v1\fixtures")
if (Test-Path (Join-Path $Src "data\v2")) {
    $v2Dst = Join-Path $Dst "data\v2"
    Ensure-Dir (Join-Path $v2Dst "outputs")
    Ensure-Dir (Join-Path $v2Dst "uploads")
    if (Test-Path (Join-Path $Src "data\v2\fixtures")) {
        Copy-Item -Recurse -Force (Join-Path $Src "data\v2\*") $v2Dst -ErrorAction SilentlyContinue
    }
}
Copy-Item -Force (Join-Path $Src "data\config\matrix_pipeline_sop.csv") (Join-Path $Dst "data\config\matrix_pipeline_sop.csv")

Get-ChildItem (Join-Path $Src "data\training\serum") -File | ForEach-Object {
    Copy-Item -Force $_.FullName (Join-Path $Dst "data\training\serum\$($_.Name)")
}

@(
    "nhanes_pfas_weighted_reference_tables_v1.csv",
    "nhanes_pfas_weighted_reference_tables_v1_1.csv",
    "nhanes_pfas_reference_tables_v1.csv"
) | ForEach-Object {
    $f = Join-Path $Src "data\reference_tables\$_"
    if (Test-Path $f) { Copy-Item -Force $f (Join-Path $Dst "data\reference_tables\$_") }
}

# Raw NHANES XPTs (large; required for lane rebuild)
if (Test-Path (Join-Path $Src "data\raw\nhanes")) {
    Copy-Item -Recurse -Force (Join-Path $Src "data\raw\nhanes\*") (Join-Path $Dst "data\raw\nhanes\")
}

# NIST external bundle (suspect list + MRT; not the nested data/external/data path)
if (Test-Path (Join-Path $Src "data\external\nist_pfas")) {
    Copy-Item -Recurse -Force (Join-Path $Src "data\external\nist_pfas\*") (Join-Path $Dst "data\external\nist_pfas\")
}

# SRM 1957 serum reference (serum lane note)
$srm = Join-Path $Src "data\reference\nist\srm1957\serum_pfas.csv"
if (Test-Path $srm) {
    Copy-Item -Force $srm (Join-Path $Dst "data\reference\nist\srm1957\serum_pfas.csv")
}

Write-Host "Done. Next: restart Shiny from $Dst and grep btn_lane_serum LatestPFAS.R"
