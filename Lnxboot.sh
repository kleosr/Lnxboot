#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/config.sh"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/cli.sh"
source "$LIB_DIR/package_manager.sh"
source "$LIB_DIR/boot_detector.sh"
source "$LIB_DIR/encryption_scanner.sh"
source "$LIB_DIR/partition_validator.sh"
source "$LIB_DIR/filesystem_manager.sh"
source "$LIB_DIR/grub_config.sh"
source "$LIB_DIR/cleanup.sh"

check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then 
        echo "[ERROR] This script requires root privileges." >&2
        echo "Usage: sudo $0 /path/to/windows.iso" >&2
        exit 1
    fi
}

validate_and_prepare_partition() {
    if [ -z "${TARGET_PARTITION:-}" ]; then
        display_partitions
        TARGET_PARTITION=$(prompt_target_partition)
        if [ $? -ne 0 ] || [ -z "$TARGET_PARTITION" ]; then
            die "No partition specified" 1
        fi
    fi
    
    if ! validate_partition_comprehensive "$TARGET_PARTITION" "$MIN_SIZE_GB"; then
        die "Partition validation failed" 1
    fi
    
    local details=$(get_partition_details "$TARGET_PARTITION")
    if [ $? -ne 0 ]; then
        die "Failed to get partition details" 1
    fi
    
    IFS=':' read -r PART_SIZE DISK_PATH PART_NUM PART_NAME <<< "$details"
    display_partition_details "$TARGET_PARTITION" "$DISK_PATH" "$PART_NUM"
    
    if ! encryption_scan_device "$DISK_PATH"; then
        exit $?
    fi
    
    if ! encryption_scan_device "$TARGET_PARTITION"; then
        exit $?
    fi
}

confirm_destructive_operation() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Dry-run mode: skipping confirmation"
        return 0
    fi
    
    if [ "$AUTO_YES" -ne 1 ]; then
        echo "[WARNING] This will erase all data on $TARGET_PARTITION" >&2
        read -p "Do you want to continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            log_info "Operation cancelled by user"
            exit 0
        fi
    else
        log_info "Auto-confirm enabled via --yes"
    fi
}

perform_installation() {
    log_info "Preparing to install Windows from $ISO_PATH to $TARGET_PARTITION"
    
    if ! create_mount_points "$MOUNT_POINT" "$ISO_MOUNT"; then
        die "Failed to create mount points" 1
    fi
    
    if ! validate_partition_not_mounted "$TARGET_PARTITION"; then
        die "Target partition is mounted" 1
    fi
    
    log_info "Formatting $TARGET_PARTITION as NTFS"
    if ! format_partition_ntfs "$TARGET_PARTITION"; then
        die "Failed to format partition as NTFS" 1
    fi
    
    log_info "Mounting Windows ISO"
    if ! mount_iso "$ISO_PATH" "$ISO_MOUNT"; then
        die "Failed to mount ISO" 1
    fi
    
    if ! validate_windows_iso "$ISO_MOUNT"; then
        die "Invalid Windows ISO: missing required files" 1
    fi
    
    if ! validate_iso_fits_partition "$ISO_MOUNT" "$PART_SIZE"; then
        die "ISO too large for target partition" 1
    fi
    
    log_info "Mounting target partition"
    if ! mount_target_partition "$TARGET_PARTITION" "$MOUNT_POINT"; then
        die "Failed to mount target partition" 1
    fi
    
    log_info "Copying Windows installation files (this may take several minutes)"
    echo "Copying files from Windows ISO to the target partition..."
    if ! copy_windows_files "$ISO_MOUNT" "$MOUNT_POINT" "$COPY_TIMEOUT_SEC"; then
        die "Failed to copy Windows files" 1
    fi
    
    log_info "Unmounting filesystems"
    umount "$ISO_MOUNT" 2>/dev/null || log_warn "Could not unmount ISO"
    umount "$MOUNT_POINT" 2>/dev/null || log_warn "Could not unmount target partition"
}

configure_grub_boot() {
    local grub_config=$(configure_grub)
    if [ $? -ne 0 ]; then
        die "Unable to determine GRUB configuration" 1
    fi
    
    IFS=':' read -r GRUB_CFG_FILE GRUB_CMD GRUB_CUSTOM_FILE <<< "$grub_config"
    
    local part_uuid=$(get_partition_uuid "$TARGET_PARTITION")
    if [ $? -ne 0 ] || [ -z "$part_uuid" ]; then
        die "Failed to retrieve partition UUID" 1
    fi
    
    PART_UUID="$part_uuid"
    
    log_info "Creating GRUB menu entry for Windows"
    if ! create_grub_entry "$PART_UUID" "$BOOT_MODE" "$GRUB_CUSTOM_FILE"; then
        die "Failed to create GRUB entry" 1
    fi
    
    if [ -z "${GRUB_CMD:-}" ] || [ -z "${GRUB_CFG_FILE:-}" ] || [ -z "${GRUB_CUSTOM_FILE:-}" ]; then
        die "Invalid GRUB configuration" 1
    fi
    
    log_info "Updating GRUB configuration"
    if ! update_grub_config "$GRUB_CMD" "$GRUB_CFG_FILE"; then
        die "Failed to update GRUB configuration" 1
    fi
}

display_completion_info() {
    echo
    echo "Windows dual-boot setup completed successfully."
    echo "============================================="
    echo "Boot Mode: $BOOT_MODE"
    echo "Target Partition: $TARGET_PARTITION"
    echo "Partition UUID: $PART_UUID"
    echo "Partition Size: $(( PART_SIZE / BYTES_PER_GB )) GB"
    echo "GRUB Configuration: $GRUB_CFG_FILE"
    echo
    echo "Boot Instructions:"
    echo "1. Restart your system"
    echo "2. Select 'Windows Installation' from the GRUB boot menu"
    echo "3. Follow the Windows installation wizard"
    echo "4. When prompted for installation location, select the partition you prepared"
    echo "   (Look for the partition labeled 'Windows' with ~$(( PART_SIZE / BYTES_PER_GB ))GB)"
    echo
    echo "Current partition status:"
    echo "-------------------------------------"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,UUID -p "$TARGET_PARTITION"
    echo
    
    echo "Important Notes:"
    echo "- Ensure Secure Boot is disabled in BIOS/UEFI settings before installation"
    case "$GRUB_CMD" in
        "update-grub")
            echo "- If Windows doesn't boot, try running: sudo update-grub"
            ;;
        "grub-mkconfig")
            echo "- If Windows doesn't boot, try running: sudo grub-mkconfig -o $GRUB_CFG_FILE"
            ;;
        "grub2-mkconfig")
            echo "- If Windows doesn't boot, try running: sudo grub2-mkconfig -o $GRUB_CFG_FILE"
            ;;
    esac
    echo "- For UEFI systems, Windows should appear in your firmware boot menu"
    echo "- After Windows installation, you may need to restore GRUB bootloader"
    echo "- A log file of this installation is available at $LOG_FILE"
    echo
    echo "System is ready for reboot."
}

main() {
    check_root_privileges
    
    parse_cli_args "$@"
    validate_iso_path
    validate_target_partition
    validate_log_file_path
    
    if [ -n "${LOG_FILE_CLI:-}" ]; then
        LOG_FILE="$LOG_FILE_CLI"
    fi
    
    init_logging "$LOG_FILE"
    setup_error_trap
    setup_cleanup_trap
    
    log_info "Starting Lnxboot - Windows Dual Boot Setup Utility"
    log_info "Script version: $(basename "$0")"
    log_info "Log file: $LOG_FILE"
    
    if ! check_requirements; then
        die "Requirements check failed" 1
    fi
    
    if [ ! -f "$ISO_PATH" ]; then
        die "Windows ISO not found: $ISO_PATH" 1
    fi
    
    BOOT_MODE=$(detect_boot_mode)
    log_info "Boot mode detected: $BOOT_MODE"
    
    validate_and_prepare_partition
    
    confirm_destructive_operation
    
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Validation complete. No changes made."
        echo "- ISO: $ISO_PATH"
        echo "- Target: $TARGET_PARTITION"
        echo "- Boot Mode: $BOOT_MODE"
        echo "- Min size (GB): $MIN_SIZE_GB"
        echo "- Log file: ${LOG_FILE}"
        exit 0
    fi
    
    perform_installation
    configure_grub_boot
    display_completion_info
    
    log_info "Installation completed successfully"
}

main "$@"
