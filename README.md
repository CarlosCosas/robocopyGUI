# Enterprise Backup GUI

Cross-platform graphical user interface for creating enterprise-grade backups with mirror synchronization.

- **Windows**: PowerShell-based GUI using Robocopy
- **Linux**: Bash/Zenity-based GUI using rsync

Both versions provide a user-friendly GUI and powerful command-line interface for file synchronization and backup operations.

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

## Platform-Specific Information

### Windows Version

**Files**: `robocopy-gui.ps1`, `robocopy.ps1`

**Requirements**:
- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- Robocopy.exe (included in Windows)
- .NET Framework (for Windows Forms GUI)

**Installation**:
1. Clone or download this repository
2. Ensure both `robocopy-gui.ps1` and `robocopy.ps1` are in the same directory
3. No additional installation required

### Linux Version

**Files**: `rsync-gui.sh`, `rsync-backup.sh`

**Requirements**:
- Linux (any modern distribution)
- Bash 4.0+
- rsync
- Zenity (for GUI)

**Installation**:
```bash
# Install dependencies (Ubuntu/Debian)
sudo apt install rsync zenity

# Install dependencies (Fedora/RHEL)
sudo dnf install rsync zenity

# Install dependencies (Arch)
sudo pacman -S rsync zenity

# Make scripts executable
chmod +x rsync-gui.sh rsync-backup.sh
```

### Version Compatibility

Both Windows and Linux versions include version checking to ensure GUI/CLI compatibility:

**Windows**:
- **GUI Version**: `robocopy-gui.ps1` v2.1.0
- **CLI Version**: `robocopy.ps1` v2.1.0
- Check version: `.\robocopy.ps1 -Version`

**Linux**:
- **GUI Version**: `rsync-gui.sh` v1.0.0
- **CLI Version**: `rsync-backup.sh` v1.0.0
- Check version: `./rsync-backup.sh --version`

⚠️ **Important**: Always keep both scripts (GUI and CLI) from the same release to avoid compatibility issues.

## Usage

### GUI Application

**Windows**:
```powershell
.\robocopy-gui.ps1
```

**Linux**:
```bash
./rsync-gui.sh
```

The GUI allows you to:
1. **Add source folders** - Select multiple folders to backup
2. **Select destination** - Choose where to store the backup
3. **Configure options** - Enable dry run, validation, parallel execution, logging, etc.
4. **Adjust settings** - Configure threading (Windows) or parallel limit (Linux)
5. **Execute** - Run the backup operation

### Command-Line Interface

**Windows**:
```powershell
.\robocopy.ps1 <source1> [source2] [...] <destination> [options]
```

**Linux**:
```bash
./rsync-backup.sh <source1> [source2] [...] <destination> [options]
```

**Important:** The last path is always treated as the destination; all preceding paths are source folders.

#### Windows Parameters (robocopy.ps1)

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

#### Linux Parameters (rsync-backup.sh)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `paths` | positional | (required) | Source folders followed by destination folder |
| `--version` | flag | - | Display script version and exit |
| `--help` | flag | - | Display help message |
| `--log` | flag | off | Enable cumulative logging to `rsync.log` |
| `--dry-run` | flag | off | Simulate execution without copying files |
| `--validate` | flag | off | Validation mode - analyze differences only |
| `--parallel` | flag | off | Execute folders in parallel |
| `--fail-fast` | flag | off | Stop on critical errors |
| `--export-json` | flag | off | Export summary to `rsync-summary.json` |
| `--throttle N` | int | 4 | Max parallel folders when using `--parallel` |
| `--no-delete` | flag | off | Disable mirror mode (don't delete extra files) |

### Examples

#### Windows Examples

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

#### Linux Examples

**Check script version:**
```bash
./rsync-backup.sh --version
```

**Basic mirror backup:**
```bash
./rsync-backup.sh /home/user/documents /home/user/projects /backup
```

**Validation before actual copy:**
```bash
./rsync-backup.sh /home/user/documents /backup --validate
```

**Dry run simulation:**
```bash
./rsync-backup.sh /home/user/documents /backup --dry-run
```

**Parallel execution with logging:**
```bash
./rsync-backup.sh /data/dir1 /data/dir2 /data/dir3 /backup --parallel --log
```

**Sync without deleting (disable mirror mode):**
```bash
./rsync-backup.sh /home/user/docs /backup --no-delete --log --export-json
```

## How It Works

### Architecture

#### Windows Implementation

- **robocopy.ps1** - Core engine that orchestrates Robocopy operations
  - Accepts multiple source folders and one destination
  - Supports parallel processing via PowerShell runspaces
  - Generates structured output as PSCustomObject
  - Note: Robocopy natively handles most long paths (>260 characters) without special prefixes

- **robocopy-gui.ps1** - Windows Forms GUI wrapper
  - Provides user-friendly interface using System.Windows.Forms
  - Validates inputs before execution
  - Builds command-line arguments from GUI controls
  - Launches robocopy.ps1 in separate PowerShell window

#### Linux Implementation

- **rsync-backup.sh** - Core engine that orchestrates rsync operations
  - Accepts multiple source folders and one destination
  - Supports parallel processing using GNU parallel or xargs
  - Generates structured output as JSON
  - Uses rsync's native capabilities for reliable synchronization

- **rsync-gui.sh** - Zenity-based GUI wrapper
  - Provides user-friendly interface using Zenity dialogs
  - Validates inputs before execution
  - Builds command-line arguments from user selections
  - Launches rsync-backup.sh in terminal (gnome-terminal, xterm, or konsole)

### Windows: Robocopy Options Used

The Windows script automatically configures Robocopy with:
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

### Linux: rsync Options Used

The Linux script automatically configures rsync with:
- `-a` - Archive mode (preserves permissions, timestamps, symbolic links)
- `-v` - Verbose output
- `--progress` - Show progress during transfer
- `--delete` - Mirror mode (when not in Validate or DryRun, unless `--no-delete` is specified)
  - ⚠️ **WARNING**: Mirror mode **DELETES files in the destination** that don't exist in the source(s)
  - This ensures the destination is an exact mirror of the source
  - Always use `--validate` or `--dry-run` first to preview changes
- `--exclude` - File and directory exclusions (fixed, not configurable):
  - Files: `desktop.ini`, `Thumbs.db`, `*.tmp`, `~*`
  - Directories: `$RECYCLE.BIN`, `System Volume Information`, `node_modules`, `site-packages`, `.git`
- `--dry-run` - Simulation mode (for DryRun and Validate modes)
- `--log-file` - Logging to file (when `--log` is specified)

### Exit Codes

**Windows (Robocopy)**:
- **0-1**: No changes / OK
- **2-3**: Files copied successfully
- **4-7**: Warnings (some files not copied)
- **>7**: Errors occurred

**Linux (rsync)**:
- **0**: Success
- **1-3**: Warnings (some files not transferred)
- **>3**: Errors occurred

## Output Files

When enabled, the scripts generate:

**Windows**:
- `robocopy.log` - Cumulative log file (with `-Log` flag)
- `robocopy-summary.json` - Structured execution summary (with `-ExportJson` flag)

**Linux**:
- `rsync.log` - Cumulative log file (with `--log` flag)
- `rsync-summary.json` - Structured execution summary (with `--export-json` flag)

All output files are created in the same directory as the script.

## Best Practices

1. **⚠️ Test First** - **ALWAYS** use validation/dry-run before running actual mirror operations
   - Windows: `-Validate` or `-DryRun`
   - Linux: `--validate` or `--dry-run`
   - Mirror mode will delete files in the destination that don't exist in source
   - Preview operations first to avoid accidental data loss
2. **Use Logging** - Enable logging for production backups to track operations
   - Windows: `-Log`
   - Linux: `--log`
3. **Parallel for Multiple Sources** - Use parallel mode when backing up multiple large folders
   - Windows: `-Parallel`
   - Linux: `--parallel`
4. **Adjust Performance Settings**
   - Windows: Increase `-MT` for large file operations on fast storage
   - Linux: Adjust `--throttle` for optimal parallel performance
5. **Monitor Exit Codes** - Use fail-fast mode for critical operations
   - Windows: `-FailFast`
   - Linux: `--fail-fast`
6. **Keep Scripts in Sync** - Always use both GUI and CLI scripts from the same release

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Author

Carlos Hoyos
