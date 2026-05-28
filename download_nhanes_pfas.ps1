# Download CDC NHANES laboratory serum PFAS XPORT (.xpt) files for offline ML.
#
# Reality check (public releases often cited for serum PFAS):
# - P_PFAS.XPT  -> 2017-March 2020 pre-pandemic laboratory file (check CDC documentation for exact cycle labeling).
# - PFAS_J.XPT  -> 2017-2018 cycle file (historical).
# - PFAS_I.XPT  -> 2015-2016 cycle file (historical).
#
# Also pulls:
# - P_DEMO.xpt (saved as P_DEMO_2017_2020.XPT): demographics + survey design fields for merges/models.
# - P_INQ.xpt (saved as P_INQ_2017_2020.XPT): family monthly poverty index fields (`INDFMMPI`, `INDFMMPC`).
#
# STRICT: serum NHANES participant rows must NOT be concatenated with UCMR drinking-water
# occurrence rows (different universe, units, and interpretation).

$ErrorActionPreference = "Stop"

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$projectRoot = $PSScriptRoot
if ($env:NHANES_PFAS_PROJECT_ROOT) {
    $projectRoot = $env:NHANES_PFAS_PROJECT_ROOT
}

$outDir = Join-Path $projectRoot "data\raw\nhanes_pfas"
if ($env:NHANES_PFAS_OUTDIR) {
    $outDir = $env:NHANES_PFAS_OUTDIR
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$downloads = @(
    @{
        Name = "P_PFAS_2017_2020.XPT"
        Url  = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_PFAS.XPT"
    },
    @{
        Name = "P_DEMO_2017_2020.XPT"
        Url  = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_DEMO.xpt"
    },
    @{
        Name = "P_INQ_2017_2020.XPT"
        Url  = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_INQ.xpt"
    },
    @{
        Name = "PFAS_J_2017_2018.XPT"
        Url  = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.XPT"
    },
    @{
        Name = "PFAS_I_2015_2016.XPT"
        Url  = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/PFAS_I.XPT"
    }
)

foreach ($d in $downloads) {
    $out = Join-Path $outDir $d.Name
    Write-Host "Downloading $($d.Name)"
    Invoke-WebRequest -Uri $d.Url -OutFile $out -UseBasicParsing
}

Write-Host "Done. Files saved to $outDir"
