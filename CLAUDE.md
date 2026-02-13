# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a PowerShell-based GUI application for creating rsync-style backups on Windows 10/11 using Robocopy. The project consists of two main components:

1. **robocopy.ps1** - Enterprise-grade command-line script with advanced Robocopy functionality
2. **robocopy-gui.ps1** - Windows Forms GUI wrapper that provides a user-friendly interface

## Architecture

### Core Scripts

**robocopy.ps1** (Backend Engine)
- Accepts multiple source folders and one destination folder via positional parameters
- The last path in `-Paths` is always the destination; all preceding paths are sources
- Implements parallel processing using PowerShell runspaces when `-Parallel` is specified
- Supports long paths (>260 characters) via `\\?\` prefix conversion
- Generates structured output as PSCustomObject for programmatic use
- Exit codes follow Robocopy conventions: 0-1 (OK), 2-3 (copied), 4-7 (warnings), >7 (errors)

**robocopy-gui.ps1** (GUI Frontend)
- Creates Windows Forms GUI using `System.Windows.Forms` and `System.Drawing`
- Must be in same directory as robocopy.ps1 (validates existence on startup)
- Builds command-line arguments from GUI controls and invokes robocopy.ps1
- Executes the script in a separate PowerShell window using `Start-Process`
- All UI text is in English

### Key Features

**Mirror Mode**: Uses Robocopy's `/MIR` flag by default (unless `-Validate` or `-DryRun` is active)
- Mirrors source to destination, deleting files that don't exist in source

**Validation Mode** (`-Validate`):
- Prevents actual mirroring/deletion by using `/L` flag
- Allows analysis of differences before running actual copy

**DryRun Mode** (`-DryRun`):
- Simulates execution without copying or modifying files

**Parallel Execution** (`-Parallel`):
- Processes multiple source folders concurrently using `ForEach-Object -Parallel`
- Controlled by `-ThrottleLimit` parameter (default: 4, max: 32)

**Long Path Support**:
- `Convert-ToLongPath` function prepends `\\?\` to paths if not already present
- Critical for Windows paths exceeding 260 characters

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

## Important Implementation Details

### Robocopy Parameters (hardcoded in script)
- `/XJ` - Excludes junction points
- `/XF desktop.ini` - Excludes desktop.ini files
- `/MT:n` - Multithreading (configurable, default: 16)
- `/R:2` - Retries on failed copies: 2
- `/W:2` - Wait time between retries: 2 seconds
- `/NP` - No progress percentage in log output

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

## Code Conventions

- English is used for all user-facing strings, comments, and UI text
- PowerShell advanced functions use `[CmdletBinding()]` and proper parameter attributes
- ScriptBlock pattern is used for parallel execution to ensure proper variable scoping
- Long paths are handled via dedicated conversion function that checks for existing prefix
- GUI uses fixed-size dialog (`FormBorderStyle = "FixedDialog"`, `MaximizeBox = $false`)

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows 10/11
- Robocopy.exe (built into Windows)
- .NET Framework for Windows Forms (System.Windows.Forms, System.Drawing)