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
Version: 2.0 Enterprise
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
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
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
    [int]$ThrottleLimit = 4
)

# =========================
# Function: Long Path Support
# =========================
function Convert-ToLongPath {
    param([string]$Path)

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

if (!(Test-Path $DestinationRoot)) {
    New-Item -ItemType Directory -Path $DestinationRoot | Out-Null
}

$DestinationRoot = Convert-ToLongPath $DestinationRoot

$LogFile = Join-Path $PSScriptRoot "robocopy.log"
$Results = @()

# =========================
# Execution ScriptBlock
# =========================
$ScriptBlock = {
    param($Source, $DestinationRoot, $MT, $Log, $DryRun, $Validate, $LogFile)

    function Convert-ToLongPathLocal {
        param([string]$Path)
        if ($Path -like "\\?\*") { return $Path }
        $full = (Resolve-Path $Path).Path
        return "\\?\$full"
    }

    $FolderName = Split-Path $Source -Leaf
    $Destination = Join-Path $DestinationRoot $FolderName

    $SourceLong = Convert-ToLongPathLocal $Source
    $DestLong   = Convert-ToLongPathLocal $Destination

    $Params = @(
        "`"$SourceLong`"",
        "`"$DestLong`"",
        "/XJ",
        "/XF", "desktop.ini",
        "/MT:$MT",
        "/R:2",
        "/W:2",
        "/NP"
    )

    if ($Validate) { $Params += "/L" }
    elseif (-not $DryRun) { $Params += "/MIR" }

    if ($DryRun) { $Params += "/L" }

    if ($Log) { $Params += "/LOG+:`"$LogFile`"" }

    robocopy @Params
    $ExitCode = $LASTEXITCODE

    [PSCustomObject]@{
        Folder   = $FolderName
        ExitCode = $ExitCode
    }
}

# =========================
# Execution
# =========================
if ($Parallel) {

    $Results = $SourceFolders | ForEach-Object -Parallel {
        & $using:ScriptBlock $_ $using:DestinationRoot $using:MT `
            $using:Log $using:DryRun $using:Validate $using:LogFile
    } -ThrottleLimit $ThrottleLimit

}
else {

    $i = 0
    foreach ($Source in $SourceFolders) {

        $i++
        $percent = [int](($i / $SourceFolders.Count) * 100)

        Write-Progress `
            -Activity "Processing folders" `
            -Status "$Source ($i of $($SourceFolders.Count))" `
            -PercentComplete $percent

        $Results += & $ScriptBlock $Source $DestinationRoot $MT `
            $Log $DryRun $Validate $LogFile
    }

    Write-Progress -Activity "Processing folders" -Completed
}

# =========================
# Results analysis
# =========================
$Success = ($Results | Where-Object { $_.ExitCode -le 1 }).Count
$Changed = ($Results | Where-Object { $_.ExitCode -ge 2 -and $_.ExitCode -le 3 }).Count
$Warnings = ($Results | Where-Object { $_.ExitCode -ge 4 -and $_.ExitCode -le 7 }).Count
$Failed = ($Results | Where-Object { $_.ExitCode -gt 7 }).Count

if ($FailFast -and $Failed -gt 0) {
    Throw "Critical failures detected in execution."
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
    Version      = "2.0 Enterprise"
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
