<#
.SYNOPSIS
Enterprise tool for copying multiple folders using Robocopy.

.DESCRIPTION
This script allows copying multiple source folders to a destination
folder using Robocopy with advanced options:

- Mirror (/MIR)
- Validation without copying (-Validate)
- Simulation (-DryRun)
- Junction exclusion (/XJ)
- Exclusion of desktop.ini
- Internal Robocopy parallelism (/MT)
- Parallelism between folders (-Parallel)
- Long path support (>260 characters)
- Optional logging
- JSON summary export
- Fail-Fast on critical errors

The last path provided in -Paths is always considered the destination.

.PARAMETER Paths
List of paths. All except the last are source folders.
The last path is the destination folder.

Example:
.\script.ps1 C:\Dir1 C:\Dir2 D:\Backup

.PARAMETER Log
Enables cumulative logging to a fixed file (robocopy.log)
located in the same directory as the script.

.PARAMETER DryRun
Simulates execution without copying or modifying files.
Equivalent to using /L in Robocopy.

.PARAMETER Validate
Validation mode. Does not perform mirroring or deletions.
Allows analyzing differences before executing an actual copy.

.PARAMETER Parallel
Executes folders in parallel using runspaces.
Speeds up execution when there are multiple sources.

.PARAMETER FailFast
Stops the script if critical errors are detected
(exit code > 7 in Robocopy).

.PARAMETER ExportJson
Exports a structured summary in JSON format
(robocopy-summary.json).

.PARAMETER MT
Defines the internal multithreading level of Robocopy.
Valid range: 1–128.
Default value: 16.

.PARAMETER ThrottleLimit
Maximum number of folders running in parallel
when using -Parallel.
Valid range: 1–32.
Default value: 4.

.INPUTS
System.String[]

.OUTPUTS
PSCustomObject (Execution summary)

.EXAMPLE
Basic mirror execution:

.\script.ps1 C:\Data C:\Projects D:\Backup

.EXAMPLE
Simulation without copying:

.\script.ps1 C:\Data C:\Projects D:\Backup -DryRun

.EXAMPLE
Validation before actual mirroring:

.\script.ps1 C:\Data C:\Projects D:\Backup -Validate

.EXAMPLE
Parallel execution with 32 internal threads:

.\script.ps1 C:\Dir1 C:\Dir2 D:\Backup -Parallel -MT 32

.EXAMPLE
Complete execution with log and JSON export:

.\script.ps1 C:\Dir1 C:\Dir2 D:\Backup -Parallel -Log -ExportJson

.NOTES
Version: 2.1.0
Requires: Windows PowerShell 5.1 or PowerShell 7+
Robocopy must be available on the system.

Robocopy exit codes:
0–1  : No changes / OK
2–3  : Files copied
4–7  : Warnings
>7   : Error

.LINK
https://learn.microsoft.com/windows-server/administration/windows-commands/robocopy
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Paths,

    [switch]$Log,
    [switch]$DryRun,
    [switch]$Validate,
    [switch]$Parallel,
    [switch]$FailFast,
    [switch]$ExportJson,

    [ValidateRange(1,128)]
    [int]$MT = 16,

    [ValidateRange(1,32)]
    [int]$ThrottleLimit = 4,

    [switch]$Version
)

# =========================
# Script Version
# =========================
$ScriptVersion = "2.1.0"
$MinimumGUIVersion = "2.1.0"

# Show version and exit if requested
if ($Version) {
    Write-Host "Robocopy Enterprise Script v$ScriptVersion"
    exit 0
}

# Validate Paths is provided when not using -Version
if ($null -eq $Paths -or $Paths.Count -eq 0) {
    Throw "You must specify at least one source folder and one destination folder. Use -Version to display version information."
}

# =========================
# Function: Long Path Support
# =========================
function Get-DestinationFolderName {
    <#
    .SYNOPSIS
    Returns the folder name a source is mirrored into beneath the destination.

    .DESCRIPTION
    Single source of truth for the duplicate-name check and the copy itself.
    Note that Split-Path returns 'C:\' for a drive root rather than an empty
    string, so roots must be matched explicitly before trusting the leaf.
    #>
    param([string]$Path)

    if ($Path -match '^([A-Za-z]):\\?$') {
        return "Drive_$($matches[1])"
    }

    $Leaf = Split-Path $Path -Leaf

    if ([string]::IsNullOrWhiteSpace($Leaf)) {
        throw "Cannot determine a destination folder name for source path: $Path"
    }

    return $Leaf
}

# =========================
# Function: Long Path Support
# =========================
function Convert-ToLongPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Cannot convert empty path to long path format"
    }

    if ($Path -like "\\?\*") { return $Path }

    $full = (Resolve-Path $Path).Path
    return "\\?\$full"
}

# =========================
# Initial validation
# =========================
if ($Paths.Count -lt 2) {
    Throw "You must specify at least one source folder and one destination folder."
}

$StartTime = Get-Date

$DestinationRoot = $Paths[-1]
$SourceFolders = $Paths[0..($Paths.Count - 2)]

# =========================
# Parameter Validation
# =========================

# Validate all source folders exist
$MissingFolders = @()
foreach ($Source in $SourceFolders) {
    if (!(Test-Path $Source -PathType Container)) {
        $MissingFolders += $Source
    }
}

if ($MissingFolders.Count -gt 0) {
    $ErrorMessage = "The following source folders do not exist:`n" + ($MissingFolders -join "`n")
    Throw $ErrorMessage
}

# The same folder listed twice is redundant intent, not a collision. Drop exact
# duplicates (order preserved) before looking for genuine name clashes.
$SeenSources = @{}
$SourceFolders = @($SourceFolders | Where-Object {
    $Full = (Resolve-Path $_).Path.TrimEnd('\')
    if ($SeenSources.ContainsKey($Full)) { $false } else { $SeenSources[$Full] = $true; $true }
})

# Each source is mirrored into <destination>\<name>, so two different sources
# resolving to the same name target one folder and the second /MIR purges the
# first. Get-DestinationFolderName is the same function the copy uses, so the
# check can never disagree with what actually happens.
$DuplicateNames = $SourceFolders |
    Group-Object { Get-DestinationFolderName $_ } |
    Where-Object { $_.Count -gt 1 }

if ($DuplicateNames) {
    $Details = $DuplicateNames | ForEach-Object {
        "  '$($_.Name)' <- " + ($_.Group -join ", ")
    }
    $CollisionMessage = "Multiple source folders share the same name and would overwrite each other in the destination:`n" +
                        ($Details -join "`n")

    # Preview modes use /L and never /MIR, so nothing can be purged: warn only.
    if ($DryRun -or $Validate) {
        Write-Warning $CollisionMessage
    }
    else {
        Throw $CollisionMessage
    }
}

# Validate destination path
if ($DestinationRoot -match '[\*\?\<\>\|]') {
    Throw "Destination path contains invalid characters: $DestinationRoot"
}

# Warn about parameter conflicts
if ($DryRun -and $Validate) {
    Write-Warning "Both -DryRun and -Validate are specified. They are equivalent: both preview without changing anything."
}

if ($Validate -and $FailFast) {
    Write-Warning "-FailFast has no effect in -Validate mode (no actual copying occurs)."
}

# Create destination if it doesn't exist
if (!(Test-Path $DestinationRoot)) {
    try {
        New-Item -ItemType Directory -Path $DestinationRoot -ErrorAction Stop | Out-Null
        Write-Verbose "Created destination directory: $DestinationRoot"
    }
    catch {
        Throw "Failed to create destination directory '$DestinationRoot': $_"
    }
}

# Validate destination is a directory
if (!(Test-Path $DestinationRoot -PathType Container)) {
    Throw "Destination path exists but is not a directory: $DestinationRoot"
}

# Note: We don't convert to long path format here because Robocopy
# doesn't work well with \\?\ prefix. The scriptblock will handle paths directly.

$LogFile = Join-Path $PSScriptRoot "robocopy.log"
$Results = @()

# =========================
# Execution ScriptBlock
# =========================
$ScriptBlock = {
    param($Source, $FolderName, $DestinationRoot, $MT, $Log, $DryRun, $Validate, $LogFile)

    # Validate source is not empty
    if ([string]::IsNullOrWhiteSpace($Source)) {
        throw "Source path is empty or null"
    }

    # Validate destination root is not empty
    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
        throw "Destination root is empty or null"
    }

    # The destination folder name is supplied by the caller via
    # Get-DestinationFolderName, so the duplicate-name check and the copy can
    # never disagree about where a source lands.
    if ([string]::IsNullOrWhiteSpace($FolderName)) {
        throw "Destination folder name is empty for source: $Source"
    }

    # Build destination path
    $Destination = Join-Path $DestinationRoot $FolderName

    # Normalize paths: remove trailing backslash for Robocopy
    # Robocopy works best with clean paths without trailing backslashes
    $SourceClean = $Source.TrimEnd('\')
    $DestClean = $Destination.TrimEnd('\')

    $Params = @(
        "`"$SourceClean`"",
        "`"$DestClean`"",
        "/E",              # Copy subdirectories, including empty ones
        "/XJ",             # Exclude junction points (reparse points)
        "/XF", "desktop.ini", "Thumbs.db", "*.tmp", "~*",  # Exclude system/temp files
        "/XD", "`$RECYCLE.BIN", "System Volume Information", "node_modules", "site-packages",  # Exclude system and dependency directories
        "/MT:$MT",
        "/R:2",
        "/W:2",
        "/NP"
    )

    # /MIR is always present, including in preview modes. Without it a preview
    # runs without /PURGE and so reports only what would be copied, staying
    # silent about the destination files a real run would delete - the half of
    # the operation a preview exists to warn about. /L makes robocopy list its
    # intentions and write nothing, so extras are reported as *EXTRA rather
    # than removed.
    $Params += "/MIR"          # Mirror mode (includes /E and /PURGE)

    if ($DryRun -or $Validate) {
        $Params += "/L"        # List only: report, change nothing
    }

    if ($Log) { $Params += "/LOG+:`"$LogFile`"" }

    # Send Robocopy's console output to the host, not down the pipeline.
    # Anything left on the pipeline is collected alongside the result object
    # below and counted as a folder in the summary.
    robocopy @Params | Write-Host
    $ExitCode = $LASTEXITCODE

    [PSCustomObject]@{
        Folder   = $FolderName
        ExitCode = $ExitCode
    }
}

# =========================
# Execution
# =========================
# Resolve each destination folder name once, up front, so every execution path
# copies to exactly the location the duplicate-name check validated.
$SourceJobs = @($SourceFolders | ForEach-Object {
    [PSCustomObject]@{
        Source     = $_
        FolderName = Get-DestinationFolderName $_
    }
})

if ($Parallel) {

    # Check PowerShell version for parallel execution support
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # PowerShell 7+ supports ForEach-Object -Parallel.
        # A ScriptBlock is bound to the runspace that created it and cannot be
        # passed in via $using:, so send the source text and rebuild it inside.
        $ScriptBlockText = $ScriptBlock.ToString()

        $Results = $SourceJobs | ForEach-Object -Parallel {
            $Body = [scriptblock]::Create($using:ScriptBlockText)
            & $Body $_.Source $_.FolderName $using:DestinationRoot $using:MT `
                $using:Log $using:DryRun $using:Validate $using:LogFile
        } -ThrottleLimit $ThrottleLimit
    }
    else {
        # PowerShell 5.1: Use Start-Job for parallel execution
        Write-Warning "PowerShell 5.1 detected. Using Start-Job for parallel execution (slower than PowerShell 7+)."

        $Jobs = @()
        foreach ($Item in $SourceJobs) {
            $Job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $Item.Source, $Item.FolderName, $DestinationRoot, $MT, $Log, $DryRun, $Validate, $LogFile
            $Jobs += $Job

            # Throttle: wait if we've reached the limit
            while (($Jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $ThrottleLimit) {
                Start-Sleep -Milliseconds 100
            }
        }

        # Wait for all jobs to complete and collect results
        $Results = $Jobs | Wait-Job | Receive-Job
        $Jobs | Remove-Job
    }

}
else {

    $i = 0
    foreach ($Item in $SourceJobs) {

        $i++
        $percent = [int](($i / $SourceJobs.Count) * 100)

        Write-Progress `
            -Activity "Processing folders" `
            -Status "$($Item.Source) ($i of $($SourceJobs.Count))" `
            -PercentComplete $percent

        $Results += & $ScriptBlock $Item.Source $Item.FolderName $DestinationRoot $MT `
            $Log $DryRun $Validate $LogFile
    }

    Write-Progress -Activity "Processing folders" -Completed
}

# =========================
# Results analysis
# =========================
# Robocopy exit codes are a bitmask, not a range: 1 = files copied,
# 2 = extra files/dirs present, 4 = mismatches, 8 = copy failures,
# 16 = fatal error. A plain successful copy returns 1, so a 0-1 "Success"
# bucket hides every copy and leaves "Changed" permanently at zero.
# Each result is classified exactly once, so the buckets sum to TotalFolders.
$Success  = 0
$Changed  = 0
$Warnings = 0
$Failed   = 0

foreach ($Result in $Results) {
    $Code = [int]$Result.ExitCode

    if ($Code -ge 8)          { $Failed++ }    # 8 = failures, 16 = fatal
    elseif ($Code -band 4)    { $Warnings++ }  # mismatched files/dirs
    elseif ($Code -band 3)    { $Changed++ }   # copied and/or extras present
    else                      { $Success++ }   # 0 = nothing to do
}

$EndTime = Get-Date
$Duration = New-TimeSpan $StartTime $EndTime

$Summary = [PSCustomObject]@{
    TotalFolders = $SourceFolders.Count
    Success      = $Success
    Changed      = $Changed
    Warnings     = $Warnings
    Failed       = $Failed
    Duration     = $Duration.ToString()
    Timestamp    = $EndTime
    Version      = $ScriptVersion
}

# =========================
# Final output
# =========================
Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
$Summary | Format-List
Write-Host "=============================="

# =========================
# Export JSON
# =========================
if ($ExportJson) {
    $JsonPath = Join-Path $PSScriptRoot "robocopy-summary.json"
    $Summary | ConvertTo-Json -Depth 3 | Out-File $JsonPath -Encoding UTF8
    Write-Host "Summary exported to: $JsonPath"
}

# =========================
# Fail-Fast
# =========================
# Thrown last, so the summary and the JSON export still record the failure
# they exist to describe.
if ($FailFast -and $Failed -gt 0) {
    Throw "Critical failures detected in execution."
}
