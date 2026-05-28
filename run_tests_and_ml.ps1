# Run Spring Boot tests and PFAS sklearn training pipeline (PowerShell).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host "== Python: install ML deps ==" -ForegroundColor Cyan
python -m pip install --upgrade pip -q
python -m pip install -r requirements-ml.txt -q

Write-Host "== Train / smoke-test sklearn pipeline ==" -ForegroundColor Cyan
if (-not $env:UCMR_DATA_PATH) {
  Write-Host "UCMR_DATA_PATH not set; script will use synthetic data." -ForegroundColor Yellow
  Write-Host 'Tip: $env:UCMR_DATA_PATH = "C:\path\to\UCMR5_533.txt"' -ForegroundColor Yellow
}
python scripts/train_ucmr_pfas.py --max-rows 250000

Write-Host "== Gradle: bootstrap wrapper (one-time download into .gradle-bootstrap) ==" -ForegroundColor Cyan
$bootstrapDir = Join-Path $Root ".gradle-bootstrap"
$gradleZip = Join-Path $bootstrapDir "gradle-8.14.3-bin.zip"
$gradleHome = Join-Path $bootstrapDir "gradle-8.14.3"
if (-not (Test-Path (Join-Path $gradleHome "bin\gradle.bat"))) {
  New-Item -ItemType Directory -Force -Path $bootstrapDir | Out-Null
  curl.exe -L --fail --retry 3 --retry-delay 2 -o $gradleZip "https://services.gradle.org/distributions/gradle-8.14.3-bin.zip"
  $zipLen = (Get-Item $gradleZip).Length
  if ($zipLen -lt 1MB) {
    throw "Gradle download looks truncated (${zipLen} bytes): $gradleZip"
  }
  Expand-Archive -Path $gradleZip -DestinationPath $bootstrapDir -Force
}
& (Join-Path $gradleHome "bin\gradle.bat") wrapper --gradle-version 8.14.3

Write-Host "== Spring Boot: tests ==" -ForegroundColor Cyan
.\gradlew.bat test --no-daemon

Write-Host "Done." -ForegroundColor Green
