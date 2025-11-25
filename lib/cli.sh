#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

ISO_PATH=""
TARGET_PARTITION=""
AUTO_YES=0
DRY_RUN=0
LOG_FILE_CLI=""

print_usage() {
    cat << 'EOF_USAGE'
Usage: lnxboot [options]

Required (choose one):
  --iso PATH               Path to Windows ISO file
  or positional ISO path   Backward-compatible: lnxboot /path/to/windows.iso

Optional:
  --target DEV             Target partition (e.g., /dev/sda3)
  --yes                    Non-interactive; auto-confirm destructive actions
  --dry-run                Validate and prepare, but do not modify disks/GRUB
  --log-file PATH          Log file path (default: /var/log/lnxboot.log)
  --min-size-gb N          Minimum target size in GB (default: 32)
  --copy-timeout-sec N     Timeout in seconds for file copy (default: 0 = none)
  -h, --help               Show this help
EOF_USAGE
}

is_positive_integer() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]
}

is_non_negative_integer() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]]
}

validate_numeric_param() {
    local param_name="$1"
    local param_value="$2"
    local allow_zero="${3:-0}"
    
    if [ -z "$param_value" ]; then
        return 1
    fi
    
    if [ "$allow_zero" -eq 1 ]; then
        if ! is_non_negative_integer "$param_value"; then
            echo "[ERROR] $param_name must be a non-negative integer"
            return 1
        fi
    else
        if ! is_positive_integer "$param_value"; then
            echo "[ERROR] $param_name must be a positive integer"
            return 1
        fi
    fi
    
    return 0
}

sanitize_path() {
    local path="$1"
    local resolved_path
    
    if [[ "$path" =~ \.\. ]]; then
        return 1
    fi
    
    resolved_path=$(readlink -f "$path" 2>/dev/null || realpath "$path" 2>/dev/null || echo "$path")
    
    if [[ "$resolved_path" =~ \.\. ]]; then
        return 1
    fi
    
    echo "$resolved_path"
    return 0
}

validate_file_path() {
    local file_path="$1"
    local description="${2:-file}"
    
    if [ -z "$file_path" ]; then
        echo "[ERROR] $description path cannot be empty"
        return 1
    fi
    
    local sanitized=$(sanitize_path "$file_path")
    if [ $? -ne 0 ]; then
        echo "[ERROR] Invalid $description path: contains path traversal attempts"
        return 1
    fi
    
    if [ ! -e "$sanitized" ]; then
        echo "[ERROR] $description does not exist: $sanitized"
        return 1
    fi
    
    if [ ! -f "$sanitized" ]; then
        echo "[ERROR] $description is not a regular file: $sanitized"
        return 1
    fi
    
    if [ ! -r "$sanitized" ]; then
        echo "[ERROR] $description is not readable: $sanitized"
        return 1
    fi
    
    echo "$sanitized"
    return 0
}

validate_device_path() {
    local device_path="$1"
    
    if [ -z "$device_path" ]; then
        echo "[ERROR] Device path cannot be empty"
        return 1
    fi
    
    if [[ ! "$device_path" =~ ^/dev/ ]]; then
        echo "[ERROR] Device path must start with /dev/: $device_path"
        return 1
    fi
    
    if [[ "$device_path" =~ \.\. ]]; then
        echo "[ERROR] Invalid device path: contains path traversal attempts"
        return 1
    fi
    
    if [ ! -b "$device_path" ] && [ ! -e "$device_path" ]; then
        echo "[ERROR] Device does not exist: $device_path"
        return 1
    fi
    
    echo "$device_path"
    return 0
}

handle_iso_option() {
    if [ -z "${2:-}" ]; then
        echo "[ERROR] --iso requires a path argument"
        print_usage
        exit 1
    fi
    ISO_PATH="${2}"
    shift 2
}

handle_target_option() {
    if [ -z "${2:-}" ]; then
        echo "[ERROR] --target requires a device argument"
        print_usage
        exit 1
    fi
    TARGET_PARTITION="${2}"
    shift 2
}

handle_log_file_option() {
    if [ -z "${2:-}" ]; then
        echo "[ERROR] --log-file requires a path argument"
        print_usage
        exit 1
    fi
    LOG_FILE_CLI="${2}"
    shift 2
}

handle_min_size_option() {
    if [ -z "${2:-}" ]; then
        echo "[ERROR] --min-size-gb requires a numeric argument"
        print_usage
        exit 1
    fi
    if ! validate_numeric_param "--min-size-gb" "${2}" 0; then
        exit 1
    fi
    MIN_SIZE_GB="${2}"
    shift 2
}

handle_copy_timeout_option() {
    if [ -z "${2:-}" ]; then
        echo "[ERROR] --copy-timeout-sec requires a numeric argument"
        print_usage
        exit 1
    fi
    if ! validate_numeric_param "--copy-timeout-sec" "${2}" 1; then
        exit 1
    fi
    COPY_TIMEOUT_SEC="${2}"
    shift 2
}

handle_positional_argument() {
    local arg="$1"
    if [ -z "${ISO_PATH}" ]; then
        ISO_PATH="$arg"
    else
        echo "[ERROR] Unexpected positional argument: $arg"
        print_usage
        exit 1
    fi
}

parse_cli_args() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi

    while [ "$#" -gt 0 ]; do
        case "${1:-}" in
            --iso)
                handle_iso_option "$@"
                ;;
            --target)
                handle_target_option "$@"
                ;;
            --yes)
                AUTO_YES=1
                shift 1
                ;;
            --dry-run)
                DRY_RUN=1
                shift 1
                ;;
            --log-file)
                handle_log_file_option "$@"
                ;;
            --min-size-gb)
                handle_min_size_option "$@"
                ;;
            --copy-timeout-sec)
                handle_copy_timeout_option "$@"
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "[ERROR] Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                handle_positional_argument "$1"
                shift 1
                ;;
        esac
    done
}

validate_iso_path() {
    if [ -z "${ISO_PATH:-}" ]; then
        echo "[ERROR] No Windows ISO path provided."
        echo "Provide with --iso /path/to/windows.iso or positional path."
        exit 1
    fi
    
    local validated_path=$(validate_file_path "$ISO_PATH" "ISO")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    ISO_PATH="$validated_path"
}

validate_target_partition() {
    if [ -n "${TARGET_PARTITION:-}" ]; then
        local validated_path=$(validate_device_path "$TARGET_PARTITION")
        if [ $? -ne 0 ]; then
            exit 1
        fi
        TARGET_PARTITION="$validated_path"
    fi
}

validate_log_file_path() {
    if [ -n "${LOG_FILE_CLI:-}" ]; then
        local sanitized=$(sanitize_path "$LOG_FILE_CLI")
        if [ $? -ne 0 ]; then
            echo "[ERROR] Invalid log file path: contains path traversal attempts"
            exit 1
        fi
        LOG_FILE_CLI="$sanitized"
    fi
}
