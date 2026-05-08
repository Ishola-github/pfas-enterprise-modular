# Run PFAS Shiny from PowerShell (uses per-user package library for this R version).
# Run from the repository root (folder that contains LatestPFAS.R and scripts/).
#
# One-time install:
#   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" --vanilla ".\scripts\install_r_deps_win_user_lib.R"
#
# Start app:
#   .\scripts\run_shiny_app.ps1
#   .\run_shiny_app.ps1
# If execution policy blocks scripts:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\run_shiny_app.ps1
#
# PowerShell env (not R): $env:PFAS_API_URL , not Sys.setenv()

param(
  [int] $Port = 3838,
  [string] $RscriptExe = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $RscriptExe)) {
  Write-Error ("Rscript not found: {0} - edit -RscriptExe or install R." -f $RscriptExe)
  exit 1
}

$RepoRoot = (Get-Location).Path
$ScriptDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path (Join-Path $RepoRoot "LatestPFAS.R"))) {
  Write-Error ("LatestPFAS.R not found in {0} - Set-Location to the repo root first." -f $RepoRoot)
  exit 1
}

$ulibR = Join-Path $ScriptDir "r_user_lib_path.R"
$ulib = (& $RscriptExe --vanilla $ulibR).Trim()
if (-not (Test-Path $ulib)) {
  Write-Warning ("User library not found: {0} - run scripts\install_r_deps_win_user_lib.R first." -f $ulib)
}

$env:R_LIBS_USER = $ulib
$appDir = $RepoRoot.Replace("\", "/")
Write-Host "R_LIBS_USER=$env:R_LIBS_USER"
Write-Host "runApp('$appDir', port=$Port)"
& $RscriptExe -e "shiny::runApp('$appDir', port=$Port)"
