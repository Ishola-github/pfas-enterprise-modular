# Run PFAS Shiny from PowerShell (uses per-user package library for this R version).
# Repo root is derived from this file's location, so you can launch via full path from any cwd:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\repo\run_shiny_app.ps1"
# Or from repo root:
#   .\scripts\run_shiny_app.ps1
#   .\run_shiny_app.ps1
#
# One-time install:
#   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" --vanilla ".\scripts\install_r_deps_win_user_lib.R"
#
# If execution policy blocks scripts:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\run_shiny_app.ps1
#
# PowerShell env (not R): $env:PFAS_API_URL , not Sys.setenv()

param(
  [int] $Port = 3838,
  [string] $RscriptExe = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
)

$ErrorActionPreference = "Stop"

if ($PSScriptRoot) {
  $ScriptDir = $PSScriptRoot
  $RepoRoot = Split-Path -Parent $ScriptDir
} else {
  $RepoRoot = (Get-Location).Path
  $ScriptDir = Join-Path $RepoRoot "scripts"
}
if (-not (Test-Path (Join-Path $RepoRoot "LatestPFAS.R"))) {
  Write-Error ('LatestPFAS.R not found in ' + $RepoRoot + ' - expected next to scripts/; reinstall or fix paths.')
  exit 1
}

if (-not (Test-Path -LiteralPath $RscriptExe)) {
  $finder = Join-Path $ScriptDir "find_rscript.ps1"
  if (Test-Path -LiteralPath $finder) {
    $lines = @(powershell.exe -NoProfile -ExecutionPolicy Bypass -File $finder 2>$null)
    if ($lines.Count -gt 0 -and $lines[0]) {
      $RscriptExe = $lines[0].ToString().Trim()
    }
  }
}
if (-not (Test-Path -LiteralPath $RscriptExe)) {
  Write-Error ('Rscript not found: ' + $RscriptExe + ' - install R, pass -RscriptExe, or run find_rscript.ps1 with Bypass.')
  exit 1
}

$ulibR = Join-Path $ScriptDir "r_user_lib_path.R"
$ulib = (& $RscriptExe --vanilla $ulibR).Trim()
if (-not (Test-Path $ulib)) {
  Write-Warning ('User library not found: ' + $ulib + ' - run scripts\install_r_deps_win_user_lib.R first.')
}

$env:R_LIBS_USER = $ulib
$appDir = $RepoRoot.Replace("\", "/")
Write-Host "R_LIBS_USER=$env:R_LIBS_USER"
Write-Host "runApp('$appDir', port=$Port)"
& $RscriptExe -e "shiny::runApp('$appDir', port=$Port)"
