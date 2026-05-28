# Three-environment confirmation -- PowerShell side.
#
# Computes SHA-256 of the four serum-lane integrity anchors using
# Windows' native Get-FileHash (BCrypt-backed) and writes the
# result deterministically to validation/serum_h_v1/.confirm_powershell.txt.
#
# Output format mirrors the bash `sha256sum` format so the
# three environments can be diffed line-for-line.

$ErrorActionPreference = 'Stop'

$files = @(
    'data/training/serum/nhanes_serum_pfas_2017_2018.csv',
    'data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv',
    'data/external/nhanes_serum_h/PFAS_H.XPT',
    'data/external/nhanes_serum_h/SSPFAS_H.XPT'
)

$out = @()
$out += "# Three-environment confirmation -- PowerShell"
$out += "# Host PSVersion: $($PSVersionTable.PSVersion)"
$out += "# Host OS:        $($PSVersionTable.OS)"
$out += "# Run timestamp:  $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
$out += ""

foreach ($rel in $files) {
    if (Test-Path $rel) {
        $h = (Get-FileHash -Algorithm SHA256 $rel).Hash.ToLower()
        $sz = (Get-Item $rel).Length
        $out += ("{0}  {1}  ({2} bytes)" -f $h, $rel, $sz)
    } else {
        $out += ("MISSING  ----------------------------------------------------------------  {0}" -f $rel)
    }
}

$dir = 'validation/serum_h_v1'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$out | Out-File -FilePath (Join-Path $dir '.confirm_powershell.txt') -Encoding ASCII
