# Verify NHANES PFAS XPT downloads and write a confirmation CSV.
#
# Usage:
#   cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
#   powershell -ExecutionPolicy Bypass -File scripts\confirm_nhanes_downloads.ps1
#
# Optional:
#   -RepoRoot "C:\Users\techj\OneDrive\Desktop\python_work\PFAS_on_R_Studio"
#   -OutCsv "data\audit\nhanes_download_confirm.csv"

param(
    [string]$RepoRoot = "",
    [string]$OutCsv = "data\audit\nhanes_download_confirm.csv",
    [string]$StagingDir = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
$OutPath = Join-Path $RepoRoot $OutCsv
$OutDir = Split-Path $OutPath -Parent
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$SasMagic = [byte[]]([System.Text.Encoding]::ASCII.GetBytes("HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!"))

function Test-XptHeader([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $magicLen = $SasMagic.Length
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] $magicLen
        $n = $fs.Read($buf, 0, $magicLen)
        if ($n -lt $magicLen) { return $false }
        for ($i = 0; $i -lt $magicLen; $i++) {
            if ($buf[$i] -ne $SasMagic[$i]) { return $false }
        }
        return $true
    }
    finally { $fs.Close() }
}

# Expected files for full pipeline (matches download_nhanes_pfas.ps1)
$expected = @(
    [pscustomobject]@{ cycle = "2013_2014"; file = "PFAS_H.XPT"; rel = "data\raw\nhanes\2013_2014\PFAS_H.XPT" }
    [pscustomobject]@{ cycle = "2013_2014"; file = "DEMO_H.XPT"; rel = "data\raw\nhanes\2013_2014\DEMO_H.XPT" }
    [pscustomobject]@{ cycle = "2015_2016"; file = "PFAS_I.XPT"; rel = "data\raw\nhanes\2015_2016\PFAS_I.XPT" }
    [pscustomobject]@{ cycle = "2015_2016"; file = "DEMO_I.XPT"; rel = "data\raw\nhanes\2015_2016\DEMO_I.XPT" }
    [pscustomobject]@{ cycle = "2017_2018"; file = "PFAS_J.XPT"; rel = "data\raw\nhanes\2017_2018\PFAS_J.XPT" }
    [pscustomobject]@{ cycle = "2017_2018"; file = "DEMO_J.XPT"; rel = "data\raw\nhanes\2017_2018\DEMO_J.XPT" }
    [pscustomobject]@{ cycle = "2017_2020"; file = "P_PFAS.XPT"; rel = "data\raw\nhanes\2017_2020\P_PFAS.XPT" }
    [pscustomobject]@{ cycle = "2017_2020"; file = "P_DEMO.XPT"; rel = "data\raw\nhanes\2017_2020\P_DEMO.XPT" }
    [pscustomobject]@{ cycle = "2013_2014"; file = "PFAS_H.XPT"; rel = "data\external\nhanes_serum_h\PFAS_H.XPT" }
    [pscustomobject]@{ cycle = "2013_2014"; file = "SSPFAS_H.XPT"; rel = "data\external\nhanes_serum_h\SSPFAS_H.XPT" }
)

# Map manual staging names (lowercase .xpt in data\external\nhanes_pfas)
$stagingAliases = @{
    "PFAS_H.XPT"   = @("PFAS_H.xpt", "PFAS_H.XPT")
    "PFAS_I.XPT"   = @("PFAS_I.xpt", "PFAS_I.XPT")
    "PFAS_J.XPT"   = @("PFAS_J.xpt", "PFAS_J.XPT")
    "P_PFAS.XPT"   = @("P_PFAS.xpt", "P_PFAS.XPT")
    "SSPFAS_H.XPT" = @("SSPFAS_H.xpt", "SSPFAS_H.XPT")
    "DEMO_H.XPT"   = @("DEMO_H.xpt", "DEMO_H.XPT")
    "DEMO_I.XPT"   = @("DEMO_I.xpt", "DEMO_I.XPT")
    "DEMO_J.XPT"   = @("DEMO_J.xpt", "DEMO_J.XPT")
    "P_DEMO.XPT"   = @("P_DEMO.xpt", "P_DEMO.XPT")
}

function Find-File([string]$Repo, [string]$Rel, [string]$BaseName) {
    $candidates = @((Join-Path $Repo $Rel))
    $aliases = $stagingAliases[$BaseName]
    if ($aliases) {
        foreach ($alias in $aliases) {
            $candidates += Join-Path $Repo "data\external\nhanes_pfas\$alias"
        }
    }
    if ($StagingDir) {
        foreach ($alias in @($BaseName) + ($aliases | ForEach-Object { $_ })) {
            if ($alias) { $candidates += Join-Path $StagingDir $alias }
        }
    }
    $homeStaging = "C:\Users\techj\data\external\nhanes_pfas"
    if (Test-Path $homeStaging) {
        foreach ($alias in @($BaseName) + ($aliases | ForEach-Object { $_ })) {
            if ($alias) { $candidates += Join-Path $homeStaging $alias }
        }
    }
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

$rows = @()
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($e in $expected) {
    $path = Find-File -Repo $RepoRoot -Rel $e.rel -BaseName $e.file
    $exists = [bool]$path
    $bytes = 0
    $sha = ""
    $xptOk = $false
    $status = "MISSING"
    if ($exists) {
        $bytes = (Get-Item $path).Length
        $sha = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $xptOk = Test-XptHeader $path
        if ($xptOk) { $status = "OK" } else { $status = "INVALID_NOT_XPT" }
    }
    $rows += [pscustomobject]@{
        confirmed_at_utc = $ts
        repo_root        = $RepoRoot
        nhanes_cycle     = $e.cycle
        expected_file    = $e.file
        expected_rel     = $e.rel
        actual_path      = $(if ($path) { $path } else { "" })
        exists           = $exists
        bytes            = $bytes
        sha256           = $sha
        xpt_header_ok    = $xptOk
        status           = $status
    }
}

$rows | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

$ok = ($rows | Where-Object { $_.status -eq "OK" }).Count
$missing = ($rows | Where-Object { $_.status -eq "MISSING" }).Count
$bad = ($rows | Where-Object { $_.status -eq "INVALID_NOT_XPT" }).Count

Write-Host "Wrote: $OutPath"
Write-Host "OK=$ok  MISSING=$missing  INVALID=$bad  TOTAL=$($rows.Count)"
$rows | Format-Table nhanes_cycle, expected_file, status, bytes, sha256 -AutoSize

if ($missing -gt 0) {
    Write-Host ""
    Write-Host "To download missing CDC files:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\download_nhanes_pfas.ps1 -IncludeSerumH"
    exit 1
}
exit 0
