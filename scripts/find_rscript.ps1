# Prints the full path to Rscript.exe (Windows). No R required.
# Usage: & .\scripts\find_rscript.ps1
# Or:    $r = & .\scripts\find_rscript.ps1

$ErrorActionPreference = "SilentlyContinue"
$candidates = @()

$regPath = "HKLM:\SOFTWARE\R-core\R"
$regPath32 = "HKLM:\SOFTWARE\WOW6432Node\R-core\R"
foreach ($rp in @($regPath, $regPath32)) {
  $ip = (Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue).InstallPath
  if ($ip -and (Test-Path $ip)) {
    $exe = Join-Path $ip "bin\Rscript.exe"
    if (Test-Path $exe) { $candidates += $exe }
  }
}

$rb = "C:\Program Files\R"
if (Test-Path $rb) {
  Get-ChildItem -Path $rb -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $exe = Join-Path $_.FullName "bin\Rscript.exe"
    if (Test-Path $exe) { $candidates += $exe }
  }
}

$which = Get-Command Rscript.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if ($which) { $candidates += $which }

$uniq = $candidates | Sort-Object -Unique
if ($uniq.Count -eq 0) {
  Write-Error "Could not find Rscript.exe. Install R from https://cran.r-project.org/ or add R's bin folder to PATH."
  exit 1
}

# Prefer highest R version in path (not lexicographic: R-4.10 beats R-4.9)
$pick = $uniq | ForEach-Object {
  $p = $_
  $v = if ($p -match 'R-(\d+)\.(\d+)\.(\d+)') { [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
  elseif ($p -match 'R-(\d+)\.(\d+)') { [version]"$($Matches[1]).$($Matches[2]).0" }
  else { [version]"0.0.0" }
  [PSCustomObject]@{ Path = $p; Ver = $v }
} | Sort-Object Ver -Descending | Select-Object -First 1 -ExpandProperty Path
Write-Output $pick
exit 0
