param(
  [string]$BaseRunId = "v1-dw-20260510-freeze",
  [string]$Seed = "42",
  [string]$Threshold = "0.25"
)

$ErrorActionPreference = "Stop"

function Write-Note([string]$msg) {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$ts] $msg"
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$validationRoot = Join-Path $projectRoot "validation\drinking_water_v1"
$runsRoot = Join-Path $validationRoot "runs"
$baseRunDir = Join-Path $runsRoot $BaseRunId

if (-not (Test-Path $baseRunDir)) {
  throw "Base run directory not found: $baseRunDir"
}

$sourceManifest = Join-Path $baseRunDir "manifest.json"
$sourceHashes = Join-Path $baseRunDir "hashes.txt"

if (-not (Test-Path $sourceManifest)) { throw "Missing base manifest: $sourceManifest" }
if (-not (Test-Path $sourceHashes)) { throw "Missing base hashes: $sourceHashes" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$repeatRoot = Join-Path $runsRoot "$BaseRunId-repeatability-$stamp"
New-Item -ItemType Directory -Path $repeatRoot -Force | Out-Null

$summaryCsv = Join-Path $repeatRoot "repeatability_summary.csv"
"run_id,repeat_index,seed,threshold,manifest_path,hashes_path,status,notes" | Out-File -FilePath $summaryCsv -Encoding UTF8

for ($i = 1; $i -le 3; $i++) {
  $rid = "$BaseRunId-repro-$i"
  $runDir = Join-Path $repeatRoot $rid
  New-Item -ItemType Directory -Path $runDir -Force | Out-Null

  $targetManifest = Join-Path $runDir "manifest.json"
  $targetHashes = Join-Path $runDir "hashes.txt"
  Copy-Item $sourceManifest $targetManifest -Force
  Copy-Item $sourceHashes $targetHashes -Force

  # Record reproducibility metadata in a sidecar to keep source manifest schema unchanged.
  $meta = [ordered]@{
    run_id        = $rid
    repeat_index  = $i
    base_run_id   = $BaseRunId
    seed          = $Seed
    threshold     = $Threshold
    created_utc   = (Get-Date).ToUniversalTime().ToString("o")
    mode          = "governed-repeatability"
    notes         = "Template repeatability scaffold. Replace with executed training/prediction outputs before scientific sign-off."
  }
  $metaPath = Join-Path $runDir "repeatability.metadata.json"
  ($meta | ConvertTo-Json -Depth 8) | Out-File -FilePath $metaPath -Encoding UTF8

  "$rid,$i,$Seed,$Threshold,$targetManifest,$targetHashes,PENDING_EXECUTION,Scaffold created; execute frozen workflow and collect metrics/artifacts." | Out-File -FilePath $summaryCsv -Encoding UTF8 -Append
  Write-Note "Prepared repeatability scaffold: $rid"
}

$summaryMd = Join-Path $repeatRoot "REPEATABILITY_SUMMARY_v1.md"
@"
# Repeatability Summary (3-Run Scaffold)

Base run: `$BaseRunId`  
Created UTC: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))  
Seed: `$Seed`  
Threshold: `$Threshold`

This scaffold is for a screening / prioritization / governance workflow.
It is not accreditation or regulatory validation evidence.

## Run Status

See CSV: `$(Split-Path -Leaf $summaryCsv)`

## Required Next Actions

1. Execute the same frozen workflow 3 times (same inputs, seed, threshold).
2. Copy metrics outputs into each repro run directory.
3. Compare metric and artifact stability.
4. Mark each run as PASS/FAIL in the CSV and complete a governed summary report.
"@ | Out-File -FilePath $summaryMd -Encoding UTF8

Write-Note "Repeatability scaffold complete: $repeatRoot"
Write-Host "Summary CSV: $summaryCsv"
Write-Host "Summary MD : $summaryMd"
