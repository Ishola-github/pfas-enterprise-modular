# Three-environment confirmation -- PowerShell (reference tables + raw XPTs).
#
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\confirm_reference_tables_powershell.ps1
#
# Writes: data/reference_tables/.confirm_powershell.txt

$ErrorActionPreference = 'Stop'
$Root = if (Test-Path (Join-Path $PSScriptRoot '..\LatestPFAS.R')) {
  (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else {
  Get-Location
}
Set-Location $Root

$files = @(
  'data/reference_tables/nhanes_pfas_reference_tables_v1.csv',
  'data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv',
  'data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv',
  'data/raw/nhanes/2013_2014/PFAS_H.XPT',
  'data/raw/nhanes/2013_2014/DEMO_H.XPT',
  'data/raw/nhanes/2015_2016/PFAS_I.XPT',
  'data/raw/nhanes/2015_2016/DEMO_I.XPT',
  'data/raw/nhanes/2017_2018/PFAS_J.XPT',
  'data/raw/nhanes/2017_2018/DEMO_J.XPT',
  'data/raw/nhanes/2017_2020/P_PFAS.XPT',
  'data/raw/nhanes/2017_2020/P_DEMO.XPT'
)

$outDir = Join-Path $Root 'data\reference_tables'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$outPath = Join-Path $outDir '.confirm_powershell.txt'

$lines = @()
$lines += '# Three-environment confirmation -- PowerShell (reference tables + raw XPTs)'
$lines += "# Host PSVersion: $($PSVersionTable.PSVersion)"
$lines += "# Host OS:        $($PSVersionTable.OS)"
$lines += "# Run timestamp:  $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
$lines += ''

foreach ($rel in $files) {
  $fp = Join-Path $Root ($rel -replace '/', '\')
  if (Test-Path $fp) {
    $h = (Get-FileHash -Algorithm SHA256 $fp).Hash.ToLower()
    $sz = (Get-Item $fp).Length
    $lines += ("{0}  {1}  ({2} bytes)" -f $h, $rel, $sz)
  } else {
    $lines += ("MISSING  ----------------------------------------------------------------  {0}" -f $rel)
  }
}

$lines | Out-File -FilePath $outPath -Encoding ascii
Write-Host "[confirm_reference_tables_powershell] wrote $outPath"
Get-Content $outPath
