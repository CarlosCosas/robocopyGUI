<#
.SYNOPSIS
Verifies by checksum that every file in a source folder reached a target folder.

.DESCRIPTION
Walks the source folder and, for each file, checks that the matching file exists
under the target folder and has the same contents.

The check is deliberately one-directional. Several sources may have been mirrored
into the same backup folder, so files present in the target but not in the source
are none of this script's business and are ignored. Only the source's files are
verified.

Files that Robocopy was told to skip (desktop.ini, Thumbs.db, *.tmp, ~*, and the
$RECYCLE.BIN, System Volume Information, node_modules and site-packages
directories) are excluded by default, since they were never copied and would
otherwise be reported as missing. Use -All to check them anyway.

A file is compared by size first and hashed only if the sizes agree, so
corrupted or truncated copies are caught without hashing the whole tree twice.

.PARAMETER Source
Folder whose files must be present in the target.

.PARAMETER Target
Folder the source was copied into. Pass the mirrored folder itself, not the
backup root: to verify C:\projA\docs, pass D:\BAK\docs.

.PARAMETER Algorithm
Hash algorithm: SHA256 (default) or MD5. MD5 is faster and adequate for
detecting copy corruption.

.PARAMETER All
Also verify files that Robocopy's exclusion lists would have skipped.

.PARAMETER MaxListed
How many problem files to list individually before switching to a percentage
summary. Default 5.

.PARAMETER ExportJson
Writes verify-summary.json next to this script.

.EXAMPLE
.\verify-backup.ps1 C:\projA\docs D:\BAK\docs

.EXAMPLE
.\verify-backup.ps1 C:\Data D:\BAK\Data -Algorithm MD5

.EXAMPLE
.\verify-backup.ps1 C:\Data D:\BAK\Data -MaxListed 20 -ExportJson

.NOTES
Version: 1.0.0
Exit codes: 0 = every file verified, 1 = one or more missing or different.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Source,

    [Parameter(Position = 1)]
    [string]$Target,

    [ValidateSet('SHA256', 'MD5')]
    [string]$Algorithm = 'SHA256',

    [switch]$All,

    [ValidateRange(0, 1000)]
    [int]$MaxListed = 5,

    [switch]$ExportJson,

    [switch]$Version
)

# =========================
# Script Version
# =========================
$ScriptVersion = "1.0.0"

if ($Version) {
    Write-Host "Backup Verify Script v$ScriptVersion"
    exit 0
}

# =========================
# Validation
# =========================
if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Target)) {
    Throw "You must specify a source folder and a target folder. Use -Version to display version information."
}

if (!(Test-Path $Source -PathType Container)) {
    Throw "Source folder does not exist: $Source"
}

if (!(Test-Path $Target -PathType Container)) {
    Throw "Target folder does not exist: $Target"
}

$SourceRoot = (Resolve-Path $Source).Path.TrimEnd('\')
$TargetRoot = (Resolve-Path $Target).Path.TrimEnd('\')

if ($SourceRoot -eq $TargetRoot) {
    Throw "Source and target are the same folder: $SourceRoot"
}

# =========================
# Exclusions (mirrors robocopy.ps1)
# =========================
$ExcludedFileNames    = @('desktop.ini', 'Thumbs.db')
$ExcludedFilePatterns = @('*.tmp', '~*')
$ExcludedDirNames     = @('$RECYCLE.BIN', 'System Volume Information', 'node_modules', 'site-packages')

function Test-IsExcluded {
    param([string]$RelativePath)

    $Segments = $RelativePath -split '\\'
    $FileName = $Segments[-1]

    if ($Segments.Count -gt 1) {
        foreach ($Segment in ($Segments | Select-Object -SkipLast 1)) {
            if ($ExcludedDirNames -contains $Segment) { return $true }
        }
    }

    if ($ExcludedFileNames -contains $FileName) { return $true }

    foreach ($Pattern in $ExcludedFilePatterns) {
        if ($FileName -like $Pattern) { return $true }
    }

    return $false
}

# =========================
# Collect source files
# =========================
$StartTime = Get-Date

Write-Host "Verifying $SourceRoot -> $TargetRoot ($Algorithm)"

$SourceFiles = @(
    Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }
)

$Checked  = 0
$Skipped  = 0
$Matched  = 0
$Problems = @()

$Total = $SourceFiles.Count
$Index = 0

foreach ($File in $SourceFiles) {

    $Index++
    $Relative = $File.FullName.Substring($SourceRoot.Length + 1)

    if (-not $All -and (Test-IsExcluded $Relative)) {
        $Skipped++
        continue
    }

    if ($Total -gt 0 -and ($Index % 25 -eq 0 -or $Index -eq $Total)) {
        Write-Progress `
            -Activity "Verifying files" `
            -Status "$Index of $Total" `
            -PercentComplete ([int](($Index / $Total) * 100))
    }

    $Checked++
    $TargetPath = Join-Path $TargetRoot $Relative

    if (!(Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        $Problems += [PSCustomObject]@{ File = $Relative; Reason = 'Missing' }
        continue
    }

    # Size is free; only hash when the sizes already agree.
    $TargetFile = Get-Item -LiteralPath $TargetPath -Force

    if ($TargetFile.Length -ne $File.Length) {
        $Problems += [PSCustomObject]@{ File = $Relative; Reason = 'Different size' }
        continue
    }

    try {
        $SourceHash = (Get-FileHash -LiteralPath $File.FullName -Algorithm $Algorithm -ErrorAction Stop).Hash
        $TargetHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm $Algorithm -ErrorAction Stop).Hash
    }
    catch {
        $Problems += [PSCustomObject]@{ File = $Relative; Reason = "Unreadable: $($_.Exception.Message)" }
        continue
    }

    if ($SourceHash -eq $TargetHash) {
        $Matched++
    }
    else {
        $Problems += [PSCustomObject]@{ File = $Relative; Reason = 'Different contents' }
    }
}

Write-Progress -Activity "Verifying files" -Completed

$Duration = New-TimeSpan $StartTime (Get-Date)

# =========================
# Report
# =========================
$Failed  = $Problems.Count
$Percent = if ($Checked -gt 0) { [math]::Round(($Failed / $Checked) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "========== VERIFICATION ==========" -ForegroundColor Cyan
Write-Host ("Files checked : {0}" -f $Checked)
Write-Host ("Matched       : {0}" -f $Matched)
Write-Host ("Problems      : {0}" -f $Failed)
Write-Host ("Skipped       : {0} (excluded by Robocopy rules)" -f $Skipped)
Write-Host ("Duration      : {0}" -f $Duration.ToString())
Write-Host "=================================="

if ($Failed -eq 0) {
    if ($Checked -eq 0) {
        Write-Warning "No files were checked. Is the source folder empty, or entirely excluded?"
    }
    else {
        Write-Host "All files verified." -ForegroundColor Green
    }
}
elseif ($Failed -le $MaxListed) {
    Write-Host ""
    Write-Host "Problem files:" -ForegroundColor Yellow
    foreach ($Problem in $Problems) {
        Write-Host ("  [{0}] {1}" -f $Problem.Reason, $Problem.File)
    }
}
else {
    Write-Warning ("{0} of {1} files ({2}%) did not verify. Too many to list; re-run with -MaxListed {0} or -ExportJson for the full list." -f $Failed, $Checked, $Percent)
}

# =========================
# Export JSON
# =========================
if ($ExportJson) {
    $Summary = [PSCustomObject]@{
        Source       = $SourceRoot
        Target       = $TargetRoot
        Algorithm    = $Algorithm
        FilesChecked = $Checked
        Matched      = $Matched
        Problems     = $Failed
        PercentFailed = $Percent
        Skipped      = $Skipped
        Duration     = $Duration.ToString()
        Timestamp    = Get-Date
        Version      = $ScriptVersion
        Details      = $Problems
    }

    $JsonPath = Join-Path $PSScriptRoot "verify-summary.json"
    $Summary | ConvertTo-Json -Depth 4 | Out-File $JsonPath -Encoding UTF8
    Write-Host "Summary exported to: $JsonPath"
}

if ($Failed -gt 0) { exit 1 } else { exit 0 }
