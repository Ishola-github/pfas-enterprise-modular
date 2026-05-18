# Assemble Validation Evidence Bundle v1 for serum demo package.
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\build_serum_validation_evidence_bundle.ps1
#
# Optional: run V1.1 + V2 first so manifests exist under data/v1|v2/outputs
#   powershell -ExecutionPolicy Bypass -File scripts\confirm_reference_tables_powershell.ps1

$ErrorActionPreference = 'Stop'
$Root = if (Test-Path (Join-Path $PSScriptRoot '..\LatestPFAS.R')) {
  (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else {
  Get-Location
}

$BundleRoot = Join-Path $Root 'validation\serum_demo_v1\evidence_bundle'
$Dirs = @('manifests', 'reports', 'confirm', 'screenshots', 'logs')
foreach ($d in $Dirs) {
  $p = Join-Path $BundleRoot $d
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Copy-IfExists($src, $dstDir) {
  if (Test-Path $src) {
    Copy-Item -Force $src (Join-Path $dstDir (Split-Path $src -Leaf))
    return $true
  }
  return $false
}

# Canonical pins
Copy-Item -Force (Join-Path $Root 'validation\serum_demo_v1\canonical_pins.json') `
  (Join-Path $BundleRoot 'canonical_pins.json')

# Reference confirmations
Copy-IfExists (Join-Path $Root 'data\reference_tables\.confirm_docker.txt') `
  (Join-Path $BundleRoot 'confirm') | Out-Null
Copy-IfExists (Join-Path $Root 'data\reference_tables\.confirm_powershell.txt') `
  (Join-Path $BundleRoot 'confirm') | Out-Null

# Hunt canonical manifests/reports in output dirs
$v2Run = '2bda057f5ab18ff6'
$v1Run = '583780b861049800'
$searchRoots = @(
  (Join-Path $Root 'data\v2\outputs'),
  (Join-Path $Root 'data\v1\outputs')
)

foreach ($base in $searchRoots) {
  if (-not (Test-Path $base)) { continue }
  Get-ChildItem $base -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name
    if ($n -match 'manifest|report') {
      if ($n -match $v2Run) {
        if ($n -match 'manifest') { Copy-Item -Force $_.FullName (Join-Path $BundleRoot 'manifests') }
        if ($n -match 'report' -and $_.Extension -match '\.(csv|pdf)$') {
          Copy-Item -Force $_.FullName (Join-Path $BundleRoot 'reports')
        }
      }
      if ($n -match $v1Run) {
        if ($n -match 'manifest') { Copy-Item -Force $_.FullName (Join-Path $BundleRoot 'manifests') }
        if ($n -match 'report' -and $_.Extension -match '\.(csv|pdf)$') {
          Copy-Item -Force $_.FullName (Join-Path $BundleRoot 'reports')
        }
      }
    }
  }
}

# hashes.txt — key artifacts
$hashLines = @()
$hashLines += ("# Validation Evidence Bundle v1 - " + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
$hashLines += "# Host: $env:COMPUTERNAME"
$hashLines += "# Repo: $Root"
$hashLines += ""

$hashTargets = @(
  'data\v1\fixtures\nhanes_j_governed_v1_input.csv',
  'data\reference_tables\nhanes_pfas_weighted_reference_tables_v1_1.csv',
  'validation\serum_demo_v1\canonical_pins.json',
  'docs\sop\PFAS_Enterprise_5_SOP_Rev2.1.md'
)
foreach ($rel in $hashTargets) {
  $fp = Join-Path $Root $rel
  if (Test-Path $fp) {
    $h = (Get-FileHash -Algorithm SHA256 $fp).Hash.ToLower()
    $sz = (Get-Item $fp).Length
    $hashLines += ("{0}  {1}  ({2} bytes)" -f $h, $rel, $sz)
  } else {
    $hashLines += ("MISSING  {0}" -f $rel)
  }
}

Get-ChildItem (Join-Path $BundleRoot 'manifests') -File -ErrorAction SilentlyContinue | ForEach-Object {
  $h = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
  $hashLines += ("{0}  evidence_bundle/manifests/{1}" -f $h, $_.Name)
}

$hashPath = Join-Path $BundleRoot 'hashes.txt'
$hashLines | Out-File -FilePath $hashPath -Encoding ascii

# BUNDLE_MANIFEST.json
try {
  $gitRev = (git -C $Root rev-parse HEAD 2>$null)
  $gitTags = (git -C $Root tag -l 'serum-*' 2>$null) -join ','
} catch {
  $gitRev = ''
  $gitTags = ''
}

$bundle = [ordered]@{
  bundle_id         = 'serum_validation_evidence_v1'
  generated_at_utc  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  repo_root         = $Root
  git_revision      = $gitRev
  serum_tags        = $gitTags
  canonical_pins    = 'canonical_pins.json'
  hashes            = 'hashes.txt'
  intended_use      = 'validation/serum_demo_v1/INTENDED_USE.txt'
  external_runbook  = 'validation/serum_demo_v1/EXTERNAL_REPRO_RUNBOOK.md'
  sop               = 'docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.md'
  note              = 'RUO - not diagnostic or regulatory. Add screenshots manually to evidence_bundle/screenshots/.'
}

$localVerify = Join-Path $Root 'validation\serum_demo_v1\evidence_bundle\LOCAL_REPRO_VERIFICATION.json'
if (Test-Path $localVerify) {
  Copy-Item -Force $localVerify (Join-Path $BundleRoot 'LOCAL_REPRO_VERIFICATION.json')
}

$jsonPath = Join-Path $BundleRoot 'BUNDLE_MANIFEST.json'
$bundle | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "[build_serum_validation_evidence_bundle] wrote $BundleRoot"
Write-Host "  BUNDLE_MANIFEST.json"
Write-Host "  hashes.txt"
Write-Host "  manifests/: $((@(Get-ChildItem (Join-Path $BundleRoot 'manifests') -File -EA SilentlyContinue)).Count) files"
Write-Host "  reports/:   $((@(Get-ChildItem (Join-Path $BundleRoot 'reports') -File -EA SilentlyContinue)).Count) files"
Write-Host ""
Write-Host "Next: add screenshots to evidence_bundle/screenshots/ per validation/serum_demo_v1/EVIDENCE_CHECKLIST.md"
