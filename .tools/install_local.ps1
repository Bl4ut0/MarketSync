[CmdletBinding()]
param(
    [ValidateSet("_anniversary_", "_classic_", "_classic_era_", "_classic_era_ptr_", "_retail_")]
    [string]$Product = "_anniversary_",

    [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FileManifest {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd("\")
    return @(
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                [PSCustomObject]@{
                    RelativePath = $_.FullName.Substring($resolvedRoot.Length).TrimStart("\")
                    Length       = $_.Length
                    SHA256       = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
                }
            }
    )
}

function Assert-ManifestsEqual {
    param(
        [Parameter(Mandatory = $true)][array]$Expected,
        [Parameter(Mandatory = $true)][array]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Expected.Count -ne $Actual.Count) {
        throw "$Label file-count mismatch: expected $($Expected.Count), found $($Actual.Count)."
    }

    $actualByPath = @{}
    foreach ($entry in $Actual) {
        $actualByPath[$entry.RelativePath] = $entry
    }

    foreach ($entry in $Expected) {
        if (-not $actualByPath.ContainsKey($entry.RelativePath)) {
            throw "$Label is missing '$($entry.RelativePath)'."
        }

        $candidate = $actualByPath[$entry.RelativePath]
        if ($candidate.Length -ne $entry.Length -or $candidate.SHA256 -ne $entry.SHA256) {
            throw "$Label hash mismatch for '$($entry.RelativePath)'."
        }
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $repoRoot "MarketSync"
$sourceToc = Join-Path $source "MarketSync.toc"

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "MarketSync source folder was not found at '$source'."
}
if (-not (Test-Path -LiteralPath $sourceToc -PathType Leaf)) {
    throw "Refusing to deploy: '$sourceToc' is missing."
}
$source = (Resolve-Path -LiteralPath $source).Path
$sourceToc = Join-Path $source "MarketSync.toc"

$resolvedWowRoot = (Resolve-Path -LiteralPath $WowRoot).Path
$productRoot = Join-Path $resolvedWowRoot $Product
$addOnsPath = Join-Path $productRoot "Interface\AddOns"
if (-not (Test-Path -LiteralPath $addOnsPath -PathType Container)) {
    throw "The requested WoW product AddOns folder does not exist: '$addOnsPath'."
}

$resolvedAddOnsPath = (Resolve-Path -LiteralPath $addOnsPath).Path.TrimEnd("\")
$target = [System.IO.Path]::GetFullPath((Join-Path $resolvedAddOnsPath "MarketSync"))
if ([System.IO.Path]::GetFullPath((Split-Path -Parent $target)).TrimEnd("\") -ne $resolvedAddOnsPath) {
    throw "Refusing to deploy outside the requested AddOns folder: '$target'."
}
if ($target -eq $source) {
    throw "Refusing to deploy the source folder onto itself."
}
if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $target -PathType Container)) {
    throw "Refusing to replace a non-directory target: '$target'."
}

$sourceManifest = Get-FileManifest -Root $source
if ($sourceManifest.Count -eq 0) {
    throw "Refusing to deploy an empty source folder."
}

$versionLine = Get-Content -LiteralPath $sourceToc | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
$version = if ($versionLine) { ($versionLine -replace '^## Version:\s*', '').Trim() } else { "unknown" }
$staging = Join-Path $resolvedAddOnsPath ("MarketSync.installing-" + [Guid]::NewGuid().ToString("N"))
$backupRoot = Join-Path $PSScriptRoot (Join-Path "backups" $Product)
$backup = Join-Path $backupRoot ("MarketSync-" + (Get-Date -Format "yyyyMMdd-HHmmssfff"))
$hadExistingInstall = Test-Path -LiteralPath $target -PathType Container
$targetWasRemoved = $false

Write-Host "Deploying MarketSync v$version to $Product"
Write-Host "  Source: $source"
Write-Host "  Target: $target"

try {
    if (Test-Path -LiteralPath $target) {
        $targetItem = Get-Item -LiteralPath $target -Force
        if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to replace a reparse-point target: '$target'."
        }

        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        $existingManifest = Get-FileManifest -Root $target
        Copy-Item -LiteralPath $target -Destination $backup -Recurse -Force
        $backupManifest = Get-FileManifest -Root $backup
        Assert-ManifestsEqual -Expected $existingManifest -Actual $backupManifest -Label "Backup copy"
        Write-Host "  Backup: $backup"
    }

    Copy-Item -LiteralPath $source -Destination $staging -Recurse -Force
    $stagingManifest = Get-FileManifest -Root $staging
    Assert-ManifestsEqual -Expected $sourceManifest -Actual $stagingManifest -Label "Staged copy"

    if (Test-Path -LiteralPath $target) {
        $targetWasRemoved = $true
        Remove-Item -LiteralPath $target -Recurse -Force
    }

    Move-Item -LiteralPath $staging -Destination $target
    $installedManifest = Get-FileManifest -Root $target
    Assert-ManifestsEqual -Expected $sourceManifest -Actual $installedManifest -Label "Installed copy"

    $tocHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $target "MarketSync.toc")).Hash
    Write-Host "Verified MarketSync v$version in ${Product}: $($installedManifest.Count) files"
    Write-Host "  MarketSync.toc SHA256: $tocHash"
}
catch {
    $failure = $_

    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }

    if ($targetWasRemoved -or -not $hadExistingInstall) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        if ($hadExistingInstall -and (Test-Path -LiteralPath $backup -PathType Container)) {
            Copy-Item -LiteralPath $backup -Destination $target -Recurse -Force
            Write-Warning "Deployment failed; the previous MarketSync installation was restored."
        }
    }

    throw $failure
}
