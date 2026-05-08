# Convenience launcher at repo root - delegates to scripts/run_shiny_app.ps1
# Usage:
#   .\run_shiny_app.ps1
#   .\run_shiny_app.ps1 -Port 8080
# From any directory (use your real path):
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\repo\run_shiny_app.ps1"
# If scripts are disabled: powershell -NoProfile -ExecutionPolicy Bypass -File .\run_shiny_app.ps1

param(
  [int] $Port = 3838,
  [string] $RscriptExe = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
)

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { $PSScriptRoot } else {
  Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
}
$inner = Join-Path $root "scripts\run_shiny_app.ps1"
if (-not (Test-Path $inner)) {
  Write-Error ('Missing ' + $inner + ' - run this from the repository root (pfas-enterprise-modular clone).')
  exit 1
}
& $inner -Port $Port -RscriptExe $RscriptExe
