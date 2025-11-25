#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

format_partition_ntfs() {
    local partition="$1"
    
    if [ -z "$partition" ]; then
        log_error "Partition path is empty"
        return 1
    fi
    
    umount "$partition" 2>/dev/null || true
    
    if command -v mkfs.ntfs >/dev/null 2>&1; then
        if ! mkfs.ntfs -f -L "$WINDOWS_LABEL" "$partition" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to format partition as NTFS using mkfs.ntfs"
            return 1
        fi
    elif command -v mkntfs >/dev/null 2>&1; then
        if ! mkntfs -f -L "$WINDOWS_LABEL" "$partition" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to format partition as NTFS using mkntfs"
            return 1
        fi
    else
        log_error "No NTFS formatting tool found (mkfs.ntfs or mkntfs)"
        return 1
    fi
    
    sync
    sleep ${FILESYSTEM_SYNC_SLEEP_SEC}
    
    if ! blkid "$partition" >/dev/null 2>&1; then
        log_warn "Cannot verify partition format immediately after formatting"
    fi
    
    return 0
}

mount_iso() {
    local iso_path="$1"
    local mount_point="$2"
    
    if [ -z "$iso_path" ] || [ -z "$mount_point" ]; then
        log_error "ISO path or mount point is empty"
        return 1
    fi
    
    if [ ! -f "$iso_path" ]; then
        log_error "ISO file does not exist: $iso_path"
        return 1
    fi
    
    if [ ! -r "$iso_path" ]; then
        log_error "ISO file is not readable: $iso_path"
        return 1
    fi
    
    if [ ! -d "$mount_point" ]; then
        log_error "Mount point does not exist: $mount_point"
        return 1
    fi
    
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_warn "Mount point is already mounted: $mount_point"
        umount "$mount_point" 2>/dev/null || true
    fi
    
    if ! mount -o loop,ro "$iso_path" "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to mount ISO: $iso_path"
        return 1
    fi
    
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_error "Mount verification failed for: $mount_point"
        return 1
    fi
    
    return 0
}

mount_target_partition() {
    local partition="$1"
    local mount_point="$2"
    
    if [ -z "$partition" ] || [ -z "$mount_point" ]; then
        log_error "Partition or mount point is empty"
        return 1
    fi
    
    if [ ! -b "$partition" ]; then
        log_error "Not a block device: $partition"
        return 1
    fi
    
    if [ ! -d "$mount_point" ]; then
        log_error "Mount point does not exist: $mount_point"
        return 1
    fi
    
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_warn "Mount point is already mounted: $mount_point"
        umount "$mount_point" 2>/dev/null || true
    fi
    
    if ! mount "$partition" "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to mount target partition: $partition"
        return 1
    fi
    
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_error "Mount verification failed for: $mount_point"
        return 1
    fi
    
    return 0
}

validate_windows_iso() {
    local iso_mount="$1"
    
    if [ -z "$iso_mount" ]; then
        log_error "ISO mount point is empty"
        return 1
    fi
    
    if [ ! -d "$iso_mount" ]; then
        log_error "ISO mount point is not a directory: $iso_mount"
        return 1
    fi
    
    if [ ! -r "$iso_mount" ]; then
        log_error "ISO mount point is not readable: $iso_mount"
        return 1
    fi
    
    local boot_wim="$iso_mount/$WINDOWS_ISO_SOURCES_PATH/$WINDOWS_ISO_BOOT_WIM"
    local install_wim="$iso_mount/$WINDOWS_ISO_SOURCES_PATH/$WINDOWS_ISO_INSTALL_WIM"
    
    if [ ! -e "$boot_wim" ] && [ ! -e "$install_wim" ]; then
        log_error "Windows ISO validation failed: missing sources/boot.wim or sources/install.wim"
        return 1
    fi
    
    return 0
}

validate_available_space() {
    local target_mount="$1"
    local required_bytes="$2"
    
    if [ -z "$target_mount" ] || [ -z "$required_bytes" ]; then
        log_error "Target mount or required bytes is empty"
        return 1
    fi
    
    if [ ! -d "$target_mount" ]; then
        log_error "Target mount is not a directory: $target_mount"
        return 1
    fi
    
    local available_bytes=$(df -B1 "$target_mount" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [ -z "$available_bytes" ] || [ "$available_bytes" -eq 0 ]; then
        log_error "Cannot determine available space for: $target_mount"
        return 1
    fi
    
    if [ "$available_bytes" -lt "$required_bytes" ]; then
        log_error "Insufficient space. Required: $(( required_bytes / BYTES_PER_GB ))GB, Available: $(( available_bytes / BYTES_PER_GB ))GB"
        return 1
    fi
    
    return 0
}

validate_iso_fits_partition() {
    local iso_mount="$1"
    local partition_size="$2"
    
    if [ -z "$iso_mount" ] || [ -z "$partition_size" ]; then
        log_error "ISO mount or partition size is empty"
        return 1
    fi
    
    if [ ! -d "$iso_mount" ]; then
        log_error "ISO mount point is not a directory: $iso_mount"
        return 1
    fi
    
    local required_bytes=$(du -sb "$iso_mount" 2>/dev/null | awk '{print $1}')
    
    if [ -z "$required_bytes" ] || [ "$required_bytes" -eq 0 ]; then
        log_error "Cannot determine ISO size"
        return 1
    fi
    
    local safety_margin=$((DEFAULT_SAFETY_MARGIN_GB * BYTES_PER_GB))
    local total_required=$((required_bytes + safety_margin))
    
    if [ "$total_required" -gt "$partition_size" ]; then
        log_error "ISO too large for partition. Required: $(( total_required / BYTES_PER_GB ))GB, Available: $(( partition_size / BYTES_PER_GB ))GB"
        return 1
    fi
    
    return 0
}

run_copy_cmd() {
    local timeout_sec="$1"
    shift
    
    if [ "$timeout_sec" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_sec" "$@"
    else
        "$@"
    fi
}

validate_copy_prerequisites() {
    local iso_mount="$1"
    local target_mount="$2"
    
    if [ -z "$iso_mount" ] || [ -z "$target_mount" ]; then
        log_error "ISO mount or target mount is empty"
        return 1
    fi
    
    if [ ! -d "$iso_mount" ] || [ ! -d "$target_mount" ]; then
        log_error "Mount points are not directories"
        return 1
    fi
    
    if [ ! -r "$iso_mount" ] || [ ! -w "$target_mount" ]; then
        log_error "Mount points lack required permissions"
        return 1
    fi
    
    return 0
}

copy_with_rsync() {
    local iso_mount="$1"
    local target_mount="$2"
    local timeout_sec="$3"
    
    if ! run_copy_cmd "$timeout_sec" rsync -a --info=progress2 "$iso_mount"/ "$target_mount"/ 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "rsync with --info=progress2 failed; retrying with rsync -a"
        if ! run_copy_cmd "$timeout_sec" rsync -a "$iso_mount"/ "$target_mount"/ 2>&1 | tee -a "$LOG_FILE"; then
            return 1
        fi
    fi
    return 0
}

copy_with_cp() {
    local iso_mount="$1"
    local target_mount="$2"
    local timeout_sec="$3"
    
    if ! run_copy_cmd "$timeout_sec" cp -a "$iso_mount"/. "$target_mount"/ 2>&1 | tee -a "$LOG_FILE"; then
        log_error "cp command failed"
        return 1
    fi
    return 0
}

copy_windows_files() {
    local iso_mount="$1"
    local target_mount="$2"
    local timeout_sec="$3"
    
    if ! validate_copy_prerequisites "$iso_mount" "$target_mount"; then
        return 1
    fi
    
    local required_bytes=$(du -sb "$iso_mount" 2>/dev/null | awk '{print $1}')
    if [ -n "$required_bytes" ] && [ "$required_bytes" -gt 0 ]; then
        if ! validate_available_space "$target_mount" "$required_bytes"; then
            return 1
        fi
    fi
    
    if command -v rsync >/dev/null 2>&1; then
        if ! copy_with_rsync "$iso_mount" "$target_mount" "$timeout_sec"; then
            log_warn "rsync failed; falling back to cp -a"
            if ! copy_with_cp "$iso_mount" "$target_mount" "$timeout_sec"; then
                log_error "All copy methods failed"
                return 1
            fi
        fi
    else
        if ! copy_with_cp "$iso_mount" "$target_mount" "$timeout_sec"; then
            return 1
        fi
    fi
    
    sync
    
    local copied_files=$(find "$target_mount" -type f 2>/dev/null | wc -l)
    log_info "Copied files: $copied_files"
    
    return 0
}

create_mount_points() {
    local mount_point="$1"
    local iso_mount="$2"
    
    if [ -z "$mount_point" ] || [ -z "$iso_mount" ]; then
        log_error "Mount point paths are empty"
        return 1
    fi
    
    rm -rf "$mount_point" "$iso_mount" 2>/dev/null || true
    
    if ! mkdir -p "$mount_point" "$iso_mount" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to create mount points"
        return 1
    fi
    
    if [ ! -d "$mount_point" ] || [ ! -d "$iso_mount" ]; then
        log_error "Mount points were not created successfully"
        return 1
    fi
    
    return 0
}
