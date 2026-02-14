#!/bin/bash

#
# rsync-backup.sh
# Enterprise tool for backing up multiple folders using rsync
#
# Version: 1.0.0
# Requires: rsync, bash 4.0+
#

set -euo pipefail

# =========================
# Script Version
# =========================
SCRIPT_VERSION="1.0.0"
MINIMUM_GUI_VERSION="1.0.0"

# =========================
# Global Variables
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/rsync.log"
JSON_FILE="$SCRIPT_DIR/rsync-summary.json"

# Default values
DRY_RUN=false
VALIDATE=false
PARALLEL=false
FAIL_FAST=false
ENABLE_LOG=false
EXPORT_JSON=false
THROTTLE_LIMIT=4
DELETE_MODE=true

# Arrays
declare -a SOURCE_FOLDERS=()
DESTINATION=""

# =========================
# Functions
# =========================

show_version() {
    echo "rsync Enterprise Backup Script v$SCRIPT_VERSION"
    exit 0
}

show_help() {
    cat <<EOF
Usage: $0 [source1] [source2] ... [destination] [options]

Enterprise tool for backing up multiple folders using rsync.

The last path is always treated as the destination; all preceding paths are source folders.

Options:
  --version           Display script version and exit
  --help              Display this help message
  --log               Enable cumulative logging to rsync.log
  --dry-run           Simulate execution without copying files
  --validate          Validation mode - analyze differences only
  --parallel          Execute folders in parallel
  --fail-fast         Stop on critical errors
  --export-json       Export summary to rsync-summary.json
  --throttle N        Max parallel folders (default: 4)
  --no-delete         Don't delete files in destination (disable mirror mode)

Examples:
  $0 /home/user/docs /home/user/projects /backup
  $0 /home/user/docs /backup --validate
  $0 /src1 /src2 /backup --parallel --log --export-json

Exit codes:
  0   : Success
  1-3 : Warnings
  >3  : Errors

EOF
    exit 0
}

log_message() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
    if [[ "$ENABLE_LOG" == true ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    fi
}

validate_dependencies() {
    if ! command -v rsync &> /dev/null; then
        echo "ERROR: rsync is not installed. Please install it first." >&2
        exit 1
    fi
}

process_folder() {
    local source="$1"
    local destination="$2"

    local folder_name=$(basename "$source")
    local dest_path="$destination/$folder_name"

    # Build rsync parameters
    local -a rsync_params=(
        "-av"                           # Archive mode, verbose
        "--progress"                    # Show progress
    )

    # Exclusions (matching robocopy exclusions)
    rsync_params+=(
        "--exclude=desktop.ini"
        "--exclude=Thumbs.db"
        "--exclude=*.tmp"
        "--exclude=~*"
        "--exclude=\$RECYCLE.BIN"
        "--exclude=System Volume Information"
        "--exclude=node_modules"
        "--exclude=site-packages"
        "--exclude=.git"
    )

    # Delete mode (mirror)
    if [[ "$DELETE_MODE" == true && "$VALIDATE" == false && "$DRY_RUN" == false ]]; then
        rsync_params+=("--delete")
    fi

    # Dry run or validate
    if [[ "$DRY_RUN" == true || "$VALIDATE" == true ]]; then
        rsync_params+=("--dry-run")
    fi

    # Logging
    if [[ "$ENABLE_LOG" == true ]]; then
        rsync_params+=("--log-file=$LOG_FILE")
    fi

    # Execute rsync
    log_message "Processing: $source -> $dest_path"

    local exit_code=0
    rsync "${rsync_params[@]}" "$source/" "$dest_path/" || exit_code=$?

    # Return result as JSON-like string
    echo "{\"folder\":\"$folder_name\",\"exit_code\":$exit_code}"

    return $exit_code
}

export -f process_folder
export -f log_message
export ENABLE_LOG DRY_RUN VALIDATE DELETE_MODE LOG_FILE

# =========================
# Parse Arguments
# =========================

declare -a PATHS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            show_version
            ;;
        --help)
            show_help
            ;;
        --log)
            ENABLE_LOG=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --validate)
            VALIDATE=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --fail-fast)
            FAIL_FAST=true
            shift
            ;;
        --export-json)
            EXPORT_JSON=true
            shift
            ;;
        --throttle)
            THROTTLE_LIMIT="$2"
            shift 2
            ;;
        --no-delete)
            DELETE_MODE=false
            shift
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            show_help
            ;;
        *)
            PATHS+=("$1")
            shift
            ;;
    esac
done

# =========================
# Validation
# =========================

validate_dependencies

if [[ ${#PATHS[@]} -lt 2 ]]; then
    echo "ERROR: You must specify at least one source folder and one destination folder." >&2
    echo "Use --help for usage information." >&2
    exit 1
fi

# Last path is destination, rest are sources
DESTINATION="${PATHS[-1]}"
unset 'PATHS[-1]'
SOURCE_FOLDERS=("${PATHS[@]}")

# Validate source folders exist
for source in "${SOURCE_FOLDERS[@]}"; do
    if [[ ! -d "$source" ]]; then
        echo "ERROR: Source folder does not exist: $source" >&2
        exit 1
    fi
done

# Create destination if it doesn't exist
if [[ ! -d "$DESTINATION" ]]; then
    log_message "Creating destination directory: $DESTINATION"
    mkdir -p "$DESTINATION"
fi

# =========================
# Execution
# =========================

START_TIME=$(date +%s)

log_message "========== STARTING BACKUP =========="
log_message "Sources: ${SOURCE_FOLDERS[*]}"
log_message "Destination: $DESTINATION"
log_message "Mirror mode: $DELETE_MODE"
log_message "Dry run: $DRY_RUN"
log_message "Validate: $VALIDATE"
log_message "Parallel: $PARALLEL"

declare -a RESULTS=()
SUCCESS_COUNT=0
WARNING_COUNT=0
FAILED_COUNT=0

if [[ "$PARALLEL" == true ]]; then
    log_message "Executing in parallel (throttle: $THROTTLE_LIMIT)"

    # Use GNU parallel if available, otherwise use xargs
    if command -v parallel &> /dev/null; then
        RESULTS=($(printf "%s\n" "${SOURCE_FOLDERS[@]}" | \
            parallel -j "$THROTTLE_LIMIT" process_folder {} "$DESTINATION"))
    else
        RESULTS=($(printf "%s\n" "${SOURCE_FOLDERS[@]}" | \
            xargs -I {} -P "$THROTTLE_LIMIT" bash -c "process_folder '{}' '$DESTINATION'"))
    fi
else
    log_message "Executing sequentially"

    local total=${#SOURCE_FOLDERS[@]}
    local current=0

    for source in "${SOURCE_FOLDERS[@]}"; do
        ((current++))
        log_message "Progress: $current/$total"

        result=$(process_folder "$source" "$DESTINATION")
        RESULTS+=("$result")

        exit_code=$(echo "$result" | grep -oP '(?<="exit_code":)\d+')

        if [[ "$FAIL_FAST" == true && $exit_code -gt 3 ]]; then
            log_message "FAIL-FAST: Critical error detected (exit code: $exit_code)"
            exit 4
        fi
    done
fi

# =========================
# Analyze Results
# =========================

for result in "${RESULTS[@]}"; do
    exit_code=$(echo "$result" | grep -oP '(?<="exit_code":)\d+' || echo "0")

    if [[ $exit_code -eq 0 ]]; then
        ((SUCCESS_COUNT++))
    elif [[ $exit_code -le 3 ]]; then
        ((WARNING_COUNT++))
    else
        ((FAILED_COUNT++))
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# =========================
# Summary
# =========================

log_message ""
log_message "========== SUMMARY =========="
log_message "Total folders: ${#SOURCE_FOLDERS[@]}"
log_message "Success: $SUCCESS_COUNT"
log_message "Warnings: $WARNING_COUNT"
log_message "Failed: $FAILED_COUNT"
log_message "Duration: ${DURATION}s"
log_message "============================="

# =========================
# Export JSON
# =========================

if [[ "$EXPORT_JSON" == true ]]; then
    cat > "$JSON_FILE" <<EOF
{
  "total_folders": ${#SOURCE_FOLDERS[@]},
  "success": $SUCCESS_COUNT,
  "warnings": $WARNING_COUNT,
  "failed": $FAILED_COUNT,
  "duration": "${DURATION}s",
  "timestamp": "$(date -Iseconds)",
  "version": "$SCRIPT_VERSION"
}
EOF
    log_message "Summary exported to: $JSON_FILE"
fi

# =========================
# Exit Code
# =========================

if [[ $FAILED_COUNT -gt 0 ]]; then
    exit 4
elif [[ $WARNING_COUNT -gt 0 ]]; then
    exit 2
else
    exit 0
fi