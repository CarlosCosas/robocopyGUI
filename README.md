# Robocopy GUI

A PowerShell-based graphical user interface for creating rsync-style backups on Windows 10/11 using Robocopy. This tool provides both a user-friendly GUI and a powerful command-line interface for enterprise-grade file synchronization and backup operations.

## Features

- **Windows Forms GUI** - Easy-to-use graphical interface for configuring backup operations
- **Multiple Source Folders** - Copy multiple source directories to a single destination
- **Mirror Mode** - Synchronize folders with `/MIR` flag (⚠️ **deletes files in destination that don't exist in source**)
- **Validation Mode** - Analyze differences before performing actual copy operations
- **Dry Run** - Simulate execution without making any changes
- **Parallel Execution** - Process multiple folders concurrently for faster backups
- **Multithreading** - Configurable Robocopy multithreading (1-128 threads)
- **Comprehensive Logging** - Optional cumulative logging to file
- **JSON Export** - Export structured summary in JSON format
- **Fail-Fast Mode** - Stop immediately on critical errors
- **Smart Exclusions** - Automatically excludes system files, temp files, and problematic directories (hardcoded, not configurable)
  - Excluded files: desktop.ini, Thumbs.db, *.tmp, ~*
  - Excluded directories: $RECYCLE.BIN, System Volume Information, node_modules, site-packages
  - Junction points (via /XJ flag)

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- Robocopy.exe (included in Windows)
- .NET Framework (for Windows Forms GUI)

## Installation

1. Clone or download this repository
2. Ensure both `robocopy-gui.ps1` and `robocopy.ps1` are in the same directory
3. No additional installation required

### Version Compatibility

The GUI and CLI scripts include version checking to ensure compatibility:
- **GUI Version**: Each `robocopy-gui.ps1` release has a version number (currently 2.1.0)
- **CLI Version**: Each `robocopy.ps1` release has a version number (currently 2.1.0)
- On startup, the GUI automatically validates that the CLI script version meets the minimum requirement
- If versions are incompatible, the GUI will display an error and refuse to launch
- You can check the CLI version manually with: `.\robocopy.ps1 -Version`

⚠️ **Important**: Always keep both scripts from the same release to avoid compatibility issues.

## Usage

### GUI Application

Launch the graphical interface:

```powershell
.\robocopy-gui.ps1
```

The GUI allows you to:
1. **Add source folders** - Select multiple folders to backup
2. **Select destination** - Choose where to store the backup
3. **Configure options** - Enable dry run, validation, parallel execution, logging, etc.
4. **Adjust threading** - Set Robocopy threads (MT) and parallel folder limit
5. **Execute** - Run the backup operation

### Command-Line Interface

For direct command-line usage or automation:

```powershell
.\robocopy.ps1 <source1> [source2] [...] <destination> [options]
```

**Important:** The last path is always treated as the destination; all preceding paths are source folders.

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Paths` | string[] | (required) | Source folders followed by destination folder |
| `-Version` | switch | off | Display script version and exit |
| `-Log` | switch | off | Enable cumulative logging to `robocopy.log` |
| `-DryRun` | switch | off | Simulate execution without copying files |
| `-Validate` | switch | off | Validation mode - analyze differences only |
| `-Parallel` | switch | off | Execute folders in parallel using runspaces |
| `-FailFast` | switch | off | Stop on critical errors (exit code > 7) |
| `-ExportJson` | switch | off | Export summary to `robocopy-summary.json` |
| `-MT` | int | 16 | Robocopy multithreading level (1-128) |
| `-ThrottleLimit` | int | 4 | Max parallel folders when using `-Parallel` (1-32) |

### Examples

**Check script version:**
```powershell
.\robocopy.ps1 -Version
```

**Basic mirror backup:**
```powershell
.\robocopy.ps1 C:\Documents C:\Projects D:\Backup
```

**Validation before actual copy:**
```powershell
.\robocopy.ps1 C:\Documents D:\Backup -Validate
```

**Dry run simulation:**
```powershell
.\robocopy.ps1 C:\Documents D:\Backup -DryRun
```

**Parallel execution with logging:**
```powershell
.\robocopy.ps1 C:\Dir1 C:\Dir2 C:\Dir3 D:\Backup -Parallel -Log
```

**Enterprise backup with all features:**
```powershell
.\robocopy.ps1 C:\Data C:\Projects D:\Backup -Parallel -MT 32 -ThrottleLimit 8 -Log -ExportJson
```

**Fail-fast mode for critical operations:**
```powershell
.\robocopy.ps1 C:\Important D:\Backup -FailFast -Log
```

## How It Works

### Architecture

- **robocopy.ps1** - Core engine that orchestrates Robocopy operations
  - Accepts multiple source folders and one destination
  - Supports parallel processing via PowerShell runspaces
  - Generates structured output as PSCustomObject
  - Note: Robocopy natively handles most long paths (>260 characters) without special prefixes

- **robocopy-gui.ps1** - Windows Forms GUI wrapper
  - Provides user-friendly interface
  - Validates inputs before execution
  - Builds command-line arguments from GUI controls
  - Launches robocopy.ps1 in separate PowerShell window

### Robocopy Options Used

The script automatically configures Robocopy with:
- `/E` - Copy subdirectories, including empty ones
- `/MIR` - Mirror mode (when not in Validate or DryRun)
  - ⚠️ **WARNING**: Mirror mode **DELETES files in the destination** that don't exist in the source(s)
  - This ensures the destination is an exact mirror of the source
  - Always use `-Validate` or `-DryRun` first to preview changes
  - Note: `/MIR` includes `/E` (subdirectories) and `/PURGE` (delete extra files)
- `/XJ` - Exclude junction points (reparse points)
- `/XF` - Exclude files (fixed exclusions, not configurable):
  - `desktop.ini` - Windows folder customization file
  - `Thumbs.db` - Windows thumbnail cache
  - `*.tmp` - Temporary files
  - `~*` - Backup/temp files
- `/XD` - Exclude directories (fixed exclusions, not configurable):
  - `$RECYCLE.BIN` - Windows Recycle Bin
  - `System Volume Information` - Windows system data
  - `node_modules` - Node.js dependencies
  - `site-packages` - Python dependencies
- `/MT:n` - Multithreading (configurable via `-MT` parameter, default: 16)
- `/R:2` - 2 retries on failed copies
- `/W:2` - 2 seconds wait between retries
- `/NP` - No progress percentage in log
- `/L` - List only (for DryRun and Validate modes)

### Exit Codes

The script follows Robocopy exit code conventions:
- **0-1**: No changes / OK
- **2-3**: Files copied successfully
- **4-7**: Warnings (some files not copied)
- **>7**: Errors occurred

## Output Files

When enabled, the script generates:
- **robocopy.log** - Cumulative log file (with `-Log` flag)
- **robocopy-summary.json** - Structured execution summary (with `-ExportJson` flag)

Both files are created in the same directory as the script.

## Best Practices

1. **⚠️ Test First** - **ALWAYS** use `-Validate` or `-DryRun` before running actual mirror operations
   - Mirror mode (`/MIR`) will delete files in the destination that don't exist in source
   - Preview operations first to avoid accidental data loss
2. **Use Logging** - Enable `-Log` for production backups to track operations
3. **Parallel for Multiple Sources** - Use `-Parallel` when backing up multiple large folders
4. **Adjust Threading** - Increase `-MT` for large file operations on fast storage
5. **Monitor Exit Codes** - Use `-FailFast` for critical operations where errors must stop execution
6. **Keep Scripts in Sync** - Always use both `robocopy-gui.ps1` and `robocopy.ps1` from the same release

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Author

Carlos Hoyos
