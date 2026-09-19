# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GUI application for creating mirror-style backups. The Windows implementation uses Robocopy; a Linux port using rsync lives alongside it.

Windows (primary):

1. **robocopy.ps1** - Enterprise-grade command-line script with advanced Robocopy functionality
2. **robocopy-gui.ps1** - Windows Forms GUI wrapper that provides a user-friendly interface

3. **verify-backup.ps1** - Standalone checksum verifier for a completed copy

Linux:

4. **rsync-backup.sh** - CLI engine mirroring the same parameter surface
5. **rsync-gui.sh** - Zenity GUI wrapper

The two platforms are independent implementations and are versioned separately (Windows 2.1.0, Linux 1.0.0).

## Architecture

### Core Scripts

**robocopy.ps1** (Backend Engine)
- Accepts multiple source folders and one destination folder via positional parameters
- The last path in `-Paths` is always the destination; all preceding paths are sources
- Implements parallel processing when `-Parallel` is specified (see Parallel Execution below)
- Generates structured output as PSCustomObject for programmatic use
- Robocopy exit codes are a **bitmask**, not a range: 1 = files copied, 2 = extras
  present, 4 = mismatches, 8 = copy failures, 16 = fatal. A plain successful copy
  returns 1, and 0 means nothing needed doing. Do not reintroduce range-based
  buckets such as `0-1 = success` — that hides every copy behind "Success".
- Long paths are **not** specially handled. Robocopy accepts >260-character paths
  natively, and the `\\?\` prefix breaks its path normalization. `Convert-ToLongPath`
  exists but is deliberately never called; see the note above the destination checks.

**robocopy-gui.ps1** (GUI Frontend)
- Creates Windows Forms GUI using `System.Windows.Forms` and `System.Drawing`
- Must be in same directory as robocopy.ps1 (validates existence on startup)
- Builds command-line arguments from GUI controls and invokes robocopy.ps1
- Executes the script in a separate PowerShell window using
  `Start-Process powershell.exe -ArgumentList` with `-File`. Do not route this
  through `cmd.exe /c` or `-Command`: the resulting double parse breaks any path
  containing a space and lets folder names execute as code.
- Paths are quoted with `ConvertTo-QuotedArgument`, which doubles a trailing run
  of backslashes. A trailing `\` before a closing quote is an argv escape, and
  `FolderBrowserDialog` returns exactly `C:\` for a drive root.
- All UI text is in English

### Key Features

**Mirror Mode**: Uses Robocopy's `/MIR` flag by default (unless `-Validate` or `-DryRun` is active)
- Mirrors source to destination, deleting files that don't exist in source

**Validation Mode** (`-Validate`) and **DryRun Mode** (`-DryRun`):
- Equivalent: both add `/L` and change nothing on disk
- `/MIR` stays on, so the listing includes the destination files that would be
  deleted (`*EXTRA`), not just the files that would be copied

**Parallel Execution** (`-Parallel`):
- Controlled by `-ThrottleLimit` parameter (default: 4, max: 32)
- **PowerShell 7+**: `ForEach-Object -Parallel`. A ScriptBlock is bound to the
  runspace that created it and cannot be passed in via `$using:`, so the body is
  sent as text and rebuilt with `[scriptblock]::Create()` inside each runspace.
- **Windows PowerShell 5.1**: falls back to `Start-Job`, throttled by polling
  job state.
- Robocopy's own output must never reach the pipeline (see Result Counting).

**Source Validation**:
- Exact duplicate source paths are de-duplicated by resolved path, order preserved.
- Two *different* sources that resolve to the same destination folder name are
  rejected: both would mirror into one folder and the second `/MIR` would purge
  the first. Under `-DryRun`/`-Validate` this warns instead of throwing, since
  those modes never pass `/MIR`.
- `Get-DestinationFolderName` is the single source of truth for where a source
  lands. It matches drive roots explicitly, because `Split-Path 'C:\' -Leaf`
  returns `C:\` rather than an empty string. A drive root maps to `Drive_<letter>`.
  The name is computed once in the caller and passed into the ScriptBlock so the
  collision check and the copy cannot disagree.

**Result Counting**:
- `robocopy @Params | Write-Host` keeps Robocopy's console output off the
  pipeline. Anything left there is collected alongside the result object, and
  because `$null -le 1` is true in PowerShell, log lines get counted as folders.
- Counts are classified once per result using the exit-code bitmask, so the
  buckets are mutually exclusive and sum to `TotalFolders`.
- `-FailFast` throws *after* the summary and JSON export, so the failure it
  exists to record is actually written.

**verify-backup.ps1** (Verifier)
- Independent of robocopy.ps1; verifies any completed copy, not just this tool's
- Takes the mirrored folder as the target, not the backup root
- **The check is one-directional by design.** Several sources may be mirrored
  into one backup folder, so files present only in the target are ignored.
  Do not "fix" this into a symmetric diff.
- Applies the same exclusion lists as robocopy.ps1, otherwise every skipped
  `desktop.ini` and `*.tmp` would be reported as missing. `-All` overrides.
- Compares size first, hashes only when sizes agree
- Exits 1 when anything failed to verify, unlike robocopy.ps1 which always exits 0

## Development Commands

### Running the GUI
```powershell
.\robocopy-gui.ps1
```

### Running the CLI Script Directly

Basic mirror of two sources to one destination:
```powershell
.\robocopy.ps1 C:\Source1 C:\Source2 D:\Destination
```

Validation (analyze without copying):
```powershell
.\robocopy.ps1 C:\Source1 D:\Destination -Validate
```

Parallel execution with logging and JSON export:
```powershell
.\robocopy.ps1 C:\Source1 C:\Source2 D:\Destination -Parallel -Log -ExportJson
```

Dry run simulation:
```powershell
.\robocopy.ps1 C:\Source1 D:\Destination -DryRun
```

### Testing

This project does not have automated tests. Manual testing approach:
1. Use `-DryRun` or `-Validate` flags to preview operations
2. Test with small non-critical folders first
3. Review generated logs and JSON summaries

When verifying behaviour, build throwaway trees under `$env:TEMP` — never point
a `/MIR` run at real data. Two techniques that make edge cases cheap to test:
- `subst X: <tempdir>` gives a real drive root to use as a source, without
  touching `C:\`. Release it with `subst X: /D`.
- Copy `robocopy.ps1` into the temp directory before testing `-ExportJson`, so
  `$PSScriptRoot` puts `robocopy-summary.json` there instead of in the repo.

## Important Implementation Details

### Robocopy Parameters (hardcoded in script)
- `/E` - Copy subdirectories, including empty ones
- `/XJ` - Excludes junction points
- `/XF` - Excludes `desktop.ini`, `Thumbs.db`, `*.tmp`, `~*`
- `/XD` - Excludes `$RECYCLE.BIN`, `System Volume Information`, `node_modules`, `site-packages`
- `/MIR` - Mirror. **Always present, including in preview modes.** Without it a
  preview runs without `/PURGE` and reports only what would be copied, hiding
  the deletions a real run would perform. `/L` is what makes a preview safe.
- `/L` - List only, added for `-Validate` and `-DryRun`. Robocopy reports its
  intentions and writes nothing, so extras appear as `*EXTRA` instead of being
  deleted.
- `/MT:n` - Multithreading (configurable, default: 16)
- `/R:2` - Retries on failed copies: 2
- `/W:2` - Wait time between retries: 2 seconds
- `/NP` - No progress percentage in log output

The exclusion lists are intentionally fixed and not configurable.

### Output Files
- **robocopy.log** - Cumulative log file (when `-Log` is used)
- **robocopy-summary.json** - Structured summary (when `-ExportJson` is used)
- Both files are created in the same directory as the script (`$PSScriptRoot`)

### GUI-to-CLI Mapping
| GUI Control | CLI Parameter |
|------------|---------------|
| Simulation (DryRun) checkbox | `-DryRun` |
| Validation checkbox | `-Validate` |
| Parallel execution checkbox | `-Parallel` |
| Save log checkbox | `-Log` |
| Export JSON summary checkbox | `-ExportJson` |
| Fail-Fast checkbox | `-FailFast` |
| Robocopy threads (MT) numeric | `-MT` |
| Parallel limit (folders) numeric | `-ThrottleLimit` |

The **Verify** button is not part of that mapping: it invokes `verify-backup.ps1`
once per source folder, pairing each source with `<destination>\<mirrored name>`.
`Get-MirroredFolderName` in the GUI must stay in step with
`Get-DestinationFolderName` in robocopy.ps1, or Verify will look in a folder the
backup never wrote to.

## Code Conventions

- English is used for all user-facing strings, comments, and UI text
- PowerShell advanced functions use `[CmdletBinding()]` and proper parameter attributes
- ScriptBlock pattern is used for parallel execution to ensure proper variable scoping
- Values the caller can compute once (such as the destination folder name) are
  passed into the ScriptBlock rather than re-derived inside it, so validation and
  execution cannot drift apart
- GUI uses fixed-size dialog (`FormBorderStyle = "FixedDialog"`, `MaximizeBox = $false`)

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows 10/11
- Robocopy.exe (built into Windows)
- .NET Framework for Windows Forms (System.Windows.Forms, System.Drawing)