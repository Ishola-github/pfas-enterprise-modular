<#
.SYNOPSIS
  Compute SHA-256 for frozen drinking-water validation bundle files and write runs/<RunId>/hashes.txt.

.DESCRIPTION
  Hashes files under validation/drinking_water_v1/artifacts and screenshots (all files),
  plus reports/FREEZE_v1.md and reports/acceptance_criteria_v1.md.
  Output paths are relative to the validation bundle root with forward slashes.

.PARAMETER RunId
  Directory name under validation/drinking_water_v1/runs/ (e.g. v1-dw-20260510-freeze or DW_V1_2026_05_10).

.PARAMETER ProjectRoot
  Repository root (folder that contains validation/ and scripts/). Default: parent of scripts/.

.PARAMETER ValidationBundleRelative
  Path segment from project root to the bundle. Default: validation/drinking_water_v1

.PARAMETER UpdateManifest
  If manifest.json exists in the run folder, add or replace artifact_paths_sha256 (path -> sha256:hex).

.EXAMPLE
  .\scripts\write_run_hashes.ps1 -RunId v1-dw-20260510-freeze

.EXAMPLE
  .\scripts\write_run_hashes.ps1 -RunId DW_V1_2026_05_10 -UpdateManifest

  If you see "running scripts is disabled on this system", use either:
  - scripts\write_run_hashes.cmd -RunId v1-dw-20260510-freeze
  - powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\write_run_hashes.ps1 -RunId v1-dw-20260510-freeze
  - Or for this session only:  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

  If -File .\scripts\... "does not exist", your cwd is not the project root. Run: cd <folder containing scripts\>
  or pass -ProjectRoot and a full path to -File (see runs/_TEMPLATE/README.md).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $RunId,

    [string] $ProjectRoot = "",

    [string] $ValidationBundleRelative = "validation\drinking_water_v1",

    [switch] $UpdateManifest
)

$ErrorActionPreference = "Stop"

if ($RunId -match '[<>:"/\\|?*]') {
    throw "RunId contains invalid path characters: $RunId"
}

if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
} else {
    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

$bundle = [System.IO.Path]::GetFullPath((Join-Path $root $ValidationBundleRelative))
if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
    throw "Validation bundle not found: $bundle"
}

$artifactsDir = Join-Path $bundle "artifacts"
$screensDir = Join-Path $bundle "screenshots"
$reportsDir = Join-Path $bundle "reports"

$reportFiles = @(
    (Join-Path $reportsDir "FREEZE_v1.md"),
    (Join-Path $reportsDir "acceptance_criteria_v1.md")
)

$files = New-Object System.Collections.Generic.List[string]

foreach ($d in @($artifactsDir, $screensDir)) {
    if (Test-Path -LiteralPath $d -PathType Container) {
        Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$files.Add($_.FullName)
        }
    }
}

foreach ($rf in $reportFiles) {
    if (Test-Path -LiteralPath $rf -PathType Leaf) {
        [void]$files.Add($rf)
    }
}

$unique = $files | Sort-Object -Unique

function Get-BundleRelativePath {
    param([string] $BasePath, [string] $FilePath)
    $b = $BasePath.TrimEnd('\', '/')
    $f = $FilePath
    if (-not $f.StartsWith($b, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $rel = $f.Substring($b.Length).TrimStart('\', '/')
    return ($rel -replace '\\', '/')
}

$entryList = foreach ($full in $unique) {
    $rel = Get-BundleRelativePath -BasePath $bundle -FilePath $full
    if ([string]::IsNullOrEmpty($rel)) { continue }
    $fh = Get-FileHash -LiteralPath $full -Algorithm SHA256
    $hex = $fh.Hash.ToLowerInvariant()
    [PSCustomObject]@{ RelPath = $rel; Hex = $hex; Prefixed = "sha256:$hex" }
}
$entries = @($entryList | Sort-Object RelPath)

$runDir = Join-Path (Join-Path $bundle "runs") $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$outFile = Join-Path $runDir "hashes.txt"
$utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# PFAS validation bundle SHA-256")
[void]$sb.AppendLine("# run_id: $RunId")
[void]$sb.AppendLine("# generated_utc: $utc")
[void]$sb.AppendLine("# project_root: $root")
[void]$sb.AppendLine("# bundle: $ValidationBundleRelative")
[void]$sb.AppendLine("# format: SHA256  <relative/path>  <64-char-hex>")
[void]$sb.AppendLine("")

foreach ($e in $entries) {
    [void]$sb.AppendLine("SHA256  $($e.RelPath)  $($e.Hex)")
}

[System.IO.File]::WriteAllText($outFile, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

Write-Host "Wrote $outFile ($($entries.Count) files)"

if ($UpdateManifest) {
    $manifestPath = Join-Path $runDir "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Warning "UpdateManifest skipped: no manifest.json at $manifestPath"
    } else {
        $raw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifest = $raw | ConvertFrom-Json

        foreach ($n in @("artifact_paths_sha256", "artifact_hashes_generated_utc")) {
            foreach ($p in @($manifest.PSObject.Properties | Where-Object { $_.Name -eq $n })) {
                [void] $manifest.PSObject.Properties.Remove($p.Name)
            }
        }

        $nested = New-Object PSObject
        foreach ($e in $entries) {
            $nested | Add-Member -MemberType NoteProperty -Name $e.RelPath -Value $e.Prefixed -Force
        }

        $manifest | Add-Member -MemberType NoteProperty -Name "artifact_paths_sha256" -Value $nested -Force
        $manifest | Add-Member -MemberType NoteProperty -Name "artifact_hashes_generated_utc" -Value $utc -Force

        $json = $manifest | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($manifestPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
        Write-Host "Updated manifest: $manifestPath"
    }
}
