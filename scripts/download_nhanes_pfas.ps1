# Download NHANES PFAS (+ DEMO) XPT files from CDC via PowerShell.
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\download_nhanes_pfas.ps1
#
# Optional: also fetch cycle-H isomer companion (SSPFAS_H) for serum_h governance:
#   powershell -ExecutionPolicy Bypass -File scripts\download_nhanes_pfas.ps1 -IncludeSerumH
#
# Files land under:
#   data/raw/nhanes/<cycle>/*.XPT
#   data/external/nhanes_serum_h/  (when -IncludeSerumH)

param(
    [string]$RepoRoot = "",
    [switch]$IncludeSerumH,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = (Resolve-Path $RepoRoot).Path

$RawRoot = Join-Path $RepoRoot "data\raw\nhanes"
$LogPath = Join-Path $RawRoot ".fetch_run.log"
$SasMagic = [byte[]]([System.Text.Encoding]::ASCII.GetBytes("HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!"))

function Write-Log([string]$Line) {
    Write-Host $Line
    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -Path $LogPath -Value $Line -Encoding utf8
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-XptHeader([string]$Path) {
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
    finally {
        $fs.Close()
    }
}

function Save-NhanesXpt {
    param(
        [string]$DestPath,
        [string[]]$Urls
    )
    $dest = [System.IO.Path]::GetFullPath($DestPath)
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    $rel = $dest.Substring($RepoRoot.Length).TrimStart('\', '/')
    if ((Test-Path $dest) -and -not $Force) {
        $sha = Get-Sha256 $dest
        $sz = (Get-Item $dest).Length
        Write-Log "$(Get-Date -Format o)  SKIP   $sha  $sz  $rel  (already present)"
        return $true
    }

    $tmp = "$dest.part"
    $headers = @{
        "User-Agent" = "pfas-toxicology-fetch/1.0 (PowerShell)"
        "Accept"     = "*/*"
    }

    $lastErr = $null
    foreach ($url in $Urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmp -Headers $headers -UseBasicParsing -TimeoutSec 120
            if (-not (Test-XptHeader $tmp)) {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                throw "Response is not a SAS Transport XPT file"
            }
            Move-Item -Force $tmp $dest
            $sha = Get-Sha256 $dest
            $sz = (Get-Item $dest).Length
            Write-Log "$(Get-Date -Format o)  OK     $sha  $sz  $rel  $url"
            return $true
        }
        catch {
            $lastErr = $_
            Write-Log "$(Get-Date -Format o)  RETRY  ----  ----  $rel  $($_.Exception.Message)"
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
        }
    }

    Write-Log "$(Get-Date -Format o)  FAIL   ----  ----  $rel  exhausted_urls last_err=$lastErr"
    return $false
}

# (cycle folder, filename, URL list) — matches scripts/fetch_nhanes_pfas_demo.py
$files = @(
    @("2013_2014", "PFAS_H.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt")),
    @("2013_2014", "DEMO_H.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/DEMO_H.xpt")),
    @("2015_2016", "PFAS_I.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/PFAS_I.xpt")),
    @("2015_2016", "DEMO_I.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/DEMO_I.xpt")),
    @("2017_2018", "PFAS_J.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.xpt")),
    @("2017_2018", "DEMO_J.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/DEMO_J.xpt")),
    @("2017_2020", "P_PFAS.XPT", @(
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_PFAS.xpt",
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017-2020/DataFiles/P_PFAS.xpt"
        )),
    @("2017_2020", "P_DEMO.XPT", @(
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_DEMO.xpt",
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017-2020/DataFiles/P_DEMO.xpt"
        ))
)

Write-Log "$(Get-Date -Format o)  START  ----  ----  --  fetcher=download_nhanes_pfas.ps1"
Write-Host "Repo: $RepoRoot"
Write-Host "Raw:  $RawRoot"

$ok = 0
$fail = 0
foreach ($entry in $files) {
    $cycle = $entry[0]
    $name = $entry[1]
    $urls = $entry[2]
    $dest = Join-Path $RawRoot "$cycle\$name"
    if (Save-NhanesXpt -DestPath $dest -Urls $urls) { $ok++ } else { $fail++ }
}

if ($IncludeSerumH) {
    $hDir = Join-Path $RepoRoot "data\external\nhanes_serum_h"
    Write-Host "Serum H companions -> $hDir"
    $serumH = @(
        @("PFAS_H.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt")),
        @("SSPFAS_H.XPT", @("https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/SSPFAS_H.xpt"))
    )
    foreach ($entry in $serumH) {
        $dest = Join-Path $hDir $entry[0]
        if (Save-NhanesXpt -DestPath $dest -Urls $entry[1]) { $ok++ } else { $fail++ }
    }
}

Write-Log "$(Get-Date -Format o)  DONE   ----  ----  --  ok=$ok fail=$fail total=$($ok + $fail)"
if ($fail -gt 0) { exit 1 }
exit 0
