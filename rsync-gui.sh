#!/bin/bash

#
# rsync-gui.sh
# Zenity GUI wrapper for rsync-backup.sh
#
# Version: 1.0.0
# Requires: zenity, bash 4.0+
#

set -euo pipefail

# =========================
# Version Information
# =========================
GUI_VERSION="1.0.0"
REQUIRED_CLI_VERSION="1.0.0"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSYNC_SCRIPT="$SCRIPT_DIR/rsync-backup.sh"

# =========================
# Dependency Check
# =========================

if ! command -v zenity &> /dev/null; then
    echo "ERROR: Zenity is not installed. Please install it first." >&2
    echo "Ubuntu/Debian: sudo apt install zenity" >&2
    echo "Fedora/RHEL: sudo dnf install zenity" >&2
    echo "Arch: sudo pacman -S zenity" >&2
    exit 1
fi

if [[ ! -f "$RSYNC_SCRIPT" ]]; then
    zenity --error --title="Error" \
        --text="Cannot find rsync-backup.sh in the same directory.\n\nExpected path: $RSYNC_SCRIPT" \
        --width=400
    exit 1
fi

if [[ ! -x "$RSYNC_SCRIPT" ]]; then
    chmod +x "$RSYNC_SCRIPT"
fi

# =========================
# Version Compatibility Check
# =========================

get_cli_version() {
    local version=$("$RSYNC_SCRIPT" --version 2>&1 | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    echo "$version"
}

check_version_compatibility() {
    local required="$1"
    local actual="$2"

    if [[ -z "$actual" ]]; then
        return 1
    fi

    # Split versions
    IFS='.' read -ra req_parts <<< "$required"
    IFS='.' read -ra act_parts <<< "$actual"

    # Check major version (must match)
    if [[ "${act_parts[0]}" != "${req_parts[0]}" ]]; then
        return 1
    fi

    # Check minor version (actual must be >= required)
    if [[ "${act_parts[1]}" -lt "${req_parts[1]}" ]]; then
        return 1
    fi

    return 0
}

CLI_VERSION=$(get_cli_version)

if [[ -z "$CLI_VERSION" ]]; then
    zenity --question --title="Version Warning" \
        --text="Cannot determine rsync-backup.sh version.\n\nThis may indicate an incompatible or corrupted script file.\n\nContinue anyway?" \
        --width=400
    if [[ $? -ne 0 ]]; then
        exit 0
    fi
elif ! check_version_compatibility "$REQUIRED_CLI_VERSION" "$CLI_VERSION"; then
    zenity --error --title="Version Mismatch" \
        --text="Version mismatch detected!\n\nGUI Version: $GUI_VERSION\nCLI Version: $CLI_VERSION\nRequired CLI Version: $REQUIRED_CLI_VERSION\n\nPlease ensure both files are from the same release." \
        --width=400
    exit 1
fi

# =========================
# GUI State Variables
# =========================

declare -a SOURCE_FOLDERS=()
DESTINATION=""

# =========================
# Main Dialog
# =========================

show_main_dialog() {
    local source_list=""
    for src in "${SOURCE_FOLDERS[@]}"; do
        source_list="$source_list• $src\n"
    done

    if [[ -z "$source_list" ]]; then
        source_list="(No source folders added)"
    fi

    local dest_text="${DESTINATION:-"(No destination selected)"}"

    local choice=$(zenity --list --title="rsync Enterprise GUI v$GUI_VERSION" \
        --text="<b>Source folders:</b>\n$source_list\n<b>Destination:</b>\n$dest_text" \
        --column="Action" --column="Description" \
        --hide-column=1 \
        --width=600 --height=400 \
        "add_source" "Add source folder" \
        "remove_source" "Remove source folder" \
        "set_destination" "Set destination folder" \
        "execute" "Execute backup" \
        "exit" "Exit" \
        2>/dev/null)

    echo "$choice"
}

# =========================
# Action Handlers
# =========================

add_source() {
    local folder=$(zenity --file-selection --directory --title="Select source folder" 2>/dev/null)
    if [[ -n "$folder" ]]; then
        SOURCE_FOLDERS+=("$folder")
        zenity --info --text="Added: $folder" --timeout=2 2>/dev/null
    fi
}

remove_source() {
    if [[ ${#SOURCE_FOLDERS[@]} -eq 0 ]]; then
        zenity --warning --text="No source folders to remove." --width=300 2>/dev/null
        return
    fi

    # Build list for selection
    local -a list_items=()
    for i in "${!SOURCE_FOLDERS[@]}"; do
        list_items+=("$i" "${SOURCE_FOLDERS[$i]}")
    done

    local selected=$(zenity --list --title="Remove source folder" \
        --text="Select folder to remove:" \
        --column="Index" --column="Path" \
        --hide-column=1 \
        --width=500 --height=300 \
        "${list_items[@]}" 2>/dev/null)

    if [[ -n "$selected" ]]; then
        unset 'SOURCE_FOLDERS[$selected]'
        SOURCE_FOLDERS=("${SOURCE_FOLDERS[@]}") # Re-index array
        zenity --info --text="Folder removed." --timeout=2 2>/dev/null
    fi
}

set_destination() {
    local folder=$(zenity --file-selection --directory --title="Select destination folder" 2>/dev/null)
    if [[ -n "$folder" ]]; then
        DESTINATION="$folder"
        zenity --info --text="Destination set: $folder" --timeout=2 2>/dev/null
    fi
}

execute_backup() {
    # Validation
    if [[ ${#SOURCE_FOLDERS[@]} -eq 0 ]]; then
        zenity --warning --text="You must add at least one source folder." --width=300 2>/dev/null
        return
    fi

    if [[ -z "$DESTINATION" ]]; then
        zenity --warning --text="You must select a destination folder." --width=300 2>/dev/null
        return
    fi

    # Options dialog
    local options=$(zenity --forms --title="Backup Options" \
        --text="Configure backup options:" \
        --add-combo="Mode:" --combo-values="Mirror (delete extra files)|Sync (no delete)" \
        --add-combo="Execution:" --combo-values="Normal|Dry Run|Validate" \
        --add-combo="Processing:" --combo-values="Sequential|Parallel" \
        --add-entry="Parallel limit:" \
        --add-combo="Logging:" --combo-values="No|Yes" \
        --add-combo="Export JSON:" --combo-values="No|Yes" \
        --add-combo="Fail-fast:" --combo-values="No|Yes" \
        --separator="|" \
        --width=400 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        return
    fi

    # Parse options
    IFS='|' read -ra opts <<< "$options"
    local mode="${opts[0]}"
    local execution="${opts[1]}"
    local processing="${opts[2]}"
    local throttle="${opts[3]:-4}"
    local logging="${opts[4]}"
    local export_json="${opts[5]}"
    local fail_fast="${opts[6]}"

    # Build command
    local -a cmd_params=()

    # Add source folders
    for src in "${SOURCE_FOLDERS[@]}"; do
        cmd_params+=("\"$src\"")
    done

    # Add destination
    cmd_params+=("\"$DESTINATION\"")

    # Add options
    if [[ "$mode" == "Sync (no delete)" ]]; then
        cmd_params+=("--no-delete")
    fi

    if [[ "$execution" == "Dry Run" ]]; then
        cmd_params+=("--dry-run")
    elif [[ "$execution" == "Validate" ]]; then
        cmd_params+=("--validate")
    fi

    if [[ "$processing" == "Parallel" ]]; then
        cmd_params+=("--parallel" "--throttle" "$throttle")
    fi

    if [[ "$logging" == "Yes" ]]; then
        cmd_params+=("--log")
    fi

    if [[ "$export_json" == "Yes" ]]; then
        cmd_params+=("--export-json")
    fi

    if [[ "$fail_fast" == "Yes" ]]; then
        cmd_params+=("--fail-fast")
    fi

    # Build command string
    local cmd_string="\"$RSYNC_SCRIPT\" ${cmd_params[*]}"

    # Confirm execution
    zenity --question --title="Confirm Execution" \
        --text="The following will be executed:\n\n<tt>$cmd_string</tt>\n\nContinue?" \
        --width=600 2>/dev/null

    if [[ $? -eq 0 ]]; then
        # Execute in terminal
        if command -v gnome-terminal &> /dev/null; then
            gnome-terminal -- bash -c "eval $cmd_string; echo ''; echo 'Press Enter to close...'; read"
        elif command -v xterm &> /dev/null; then
            xterm -hold -e bash -c "eval $cmd_string"
        elif command -v konsole &> /dev/null; then
            konsole --hold -e bash -c "eval $cmd_string"
        else
            # Fallback: show progress with zenity
            eval "$cmd_string" | zenity --progress --title="Backup in Progress" --pulsate --auto-close 2>/dev/null
        fi

        zenity --info --text="Backup execution completed.\n\nCheck the terminal window for details." --width=400 2>/dev/null
    fi
}

# =========================
# Main Loop
# =========================

while true; do
    action=$(show_main_dialog)

    case "$action" in
        add_source)
            add_source
            ;;
        remove_source)
            remove_source
            ;;
        set_destination)
            set_destination
            ;;
        execute)
            execute_backup
            ;;
        exit|"")
            exit 0
            ;;
    esac
done