# Assemble reproducibility release folder + refresh reviewer ZIP.
#
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\build_reproducibility_release.ps1

$ErrorActionPreference = 'Stop'
$Root = if (Test-Path (Join-Path $PSScriptRoot '..\LatestPFAS.R')) {
  (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else { Get-Location }
Set-Location $Root

$ReleaseDir = Join-Path $Root 'validation\releases\serum-v2.0.0-temporal'
$DemoDir = Join-Path $Root 'validation\serum_demo_v1'

# Refresh reviewer ZIP (program + quickstart)
$zipItems = @(
  'README.md',
  'ONE_COMMAND_REPRO.md',
  'REVIEWER_ATTESTATION_MINIMAL.txt',
  'QUICKSTART_5MIN.md',
  'REPRODUCIBILITY_PROGRAM.md',
  'BLIND_EXTERNAL_REPRO_PROTOCOL.md',
  'EXTERNAL_REPRO_RUNBOOK.md',
  'EXTERNAL_REVIEWER_PACKET.md',
  'EVIDENCE_CHECKLIST.md',
  'REVIEWER_ATTESTATION_TEMPLATE.txt',
  'canonical_pins.json',
  'INTENDED_USE.txt'
) | ForEach-Object { Join-Path $DemoDir $_ }

$zipPath = Join-Path $DemoDir 'serum_demo_reviewer_packet.zip'
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path $zipItems -DestinationPath $zipPath -Force

# Copy zip into release folder for GitHub Release upload
if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null }
Copy-Item -Force $zipPath (Join-Path $ReleaseDir 'serum_demo_reviewer_packet.zip')
Copy-Item -Force (Join-Path $DemoDir 'canonical_pins.json') (Join-Path $ReleaseDir 'canonical_pins.json')

Write-Host "[build_reproducibility_release] OK"
Write-Host "  ZIP: $zipPath"
Write-Host "  Release copy: $ReleaseDir"
Write-Host "  Next: add screenshots under validation\releases\serum-v2.0.0-temporal\screenshots\ci\"
Write-Host "  Then: GitHub Release + Zenodo per docs\ZENODO_ARCHIVE.md"
