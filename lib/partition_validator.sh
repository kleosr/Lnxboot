#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

validate_partition_exists() {
    local partition="$1"
    if [ -z "$partition" ]; then
        log_error "Partition path is empty"
        return 1
    fi
    
    if [[ ! "$partition" =~ ^/dev/ ]]; then
        log_error "Invalid partition path format: $partition"
        return 1
    fi
    
    if ! lsblk "$partition" >/dev/null 2>&1; then
        log_error "Partition does not exist: $partition"
        return 1
    fi
    
    if [ ! -b "$partition" ]; then
        log_error "Path is not a block device: $partition"
        return 1
    fi
    
    return 0
}

validate_partition_is_partition() {
    local partition="$1"
    local part_type=$(lsblk -no TYPE "$partition" 2>/dev/null || echo "")
    
    if [ -z "$part_type" ]; then
        log_error "Cannot determine partition type for: $partition"
        return 1
    fi
    
    if [ "$part_type" != "part" ]; then
        log_error "Target must be a partition (type: $part_type), not a whole disk"
        return 1
    fi
    
    return 0
}

validate_partition_not_efi() {
    local partition="$1"
    local part_type=$(lsblk -no PARTTYPE "$partition" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    
    if [ "$part_type" = "$EFI_GUID" ]; then
        log_error "The selected partition appears to be the EFI System Partition"
        return 1
    fi
    
    return 0
}

validate_partition_not_managed_volume() {
    local partition="$1"
    local fstype=$(lsblk -no FSTYPE "$partition" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    
    if [[ "${fstype}" =~ ^(crypto_luks|lvm2_member|linux_raid_member)$ ]]; then
        log_error "Target partition is a managed volume (${fstype})"
        return 1
    fi
    
    return 0
}

validate_partition_not_mounted_as_esp() {
    local partition="$1"
    local mountpoint=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null | head -n1 || echo "")
    
    if [ -n "${mountpoint:-}" ] && [[ "${mountpoint}" =~ ^(/boot/efi|/efi)$ ]]; then
        log_error "The selected partition is mounted as the EFI System Partition (${mountpoint})"
        return 1
    fi
    
    return 0
}

validate_partition_not_system_partition() {
    local partition="$1"
    local root_src=$(findmnt -no SOURCE / 2>/dev/null || echo "")
    local boot_src=$(findmnt -no SOURCE /boot 2>/dev/null || echo "")
    local esp_src=$(findmnt -no SOURCE /boot/efi 2>/dev/null || echo "")
    
    if [ -n "${root_src:-}" ] && [ "$partition" = "$root_src" ]; then
        log_error "Target partition is the current root filesystem device"
        return 1
    fi
    
    if [ -n "${boot_src:-}" ] && [ "$partition" = "$boot_src" ]; then
        log_error "Target partition is the current /boot device"
        return 1
    fi
    
    if [ -n "${esp_src:-}" ] && [ "$partition" = "$esp_src" ]; then
        log_error "Target partition is the current EFI System Partition"
        return 1
    fi
    
    return 0
}

validate_partition_size() {
    local partition="$1"
    local min_size_gb="$2"
    local part_size=$(lsblk -b -n -o SIZE "$partition" 2>/dev/null | head -n1)
    
    if [ -z "$part_size" ] || [ "$part_size" -eq 0 ]; then
        log_error "Cannot determine partition size for: $partition"
        return 1
    fi
    
    local min_size=$((min_size_gb * BYTES_PER_GB))
    
    if [ "$part_size" -lt "$min_size" ]; then
        log_error "Partition too small. Required: ${min_size_gb}GB, Available: $(( part_size / BYTES_PER_GB ))GB"
        return 1
    fi
    
    return 0
}

validate_partition_not_mounted() {
    local partition="$1"
    local mountpoint=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null | head -n1 || echo "")
    
    if [ -n "${mountpoint:-}" ]; then
        log_error "Target partition is currently mounted at ${mountpoint}"
        return 1
    fi
    
    local mount_check=$(findmnt -n -o TARGET "$partition" 2>/dev/null || echo "")
    if [ -n "$mount_check" ]; then
        log_error "Partition is mounted via findmnt at: $mount_check"
        return 1
    fi
    
    return 0
}

validate_partition_permissions() {
    local partition="$1"
    
    if [ ! -r "$partition" ]; then
        log_error "Cannot read partition: $partition"
        return 1
    fi
    
    if [ ! -w "$partition" ]; then
        log_warn "Partition is not writable: $partition (may require root privileges)"
    fi
    
    return 0
}

get_partition_details() {
    local partition="$1"
    local part_size=$(lsblk -b -n -o SIZE "$partition" 2>/dev/null | head -n1)
    local disk_name=$(lsblk -no pkname "$partition" 2>/dev/null || echo "")
    local disk_path="/dev/$disk_name"
    local part_num=$(lsblk -no PARTNUM "$partition" 2>/dev/null | head -n1 || echo "")
    local part_name=$(basename "$partition")
    
    if [ -z "$part_size" ] || [ "$part_size" -eq 0 ]; then
        log_error "Cannot retrieve partition details for: $partition"
        return 1
    fi
    
    echo "$part_size:$disk_path:$part_num:$part_name"
    return 0
}

display_partitions() {
    echo "Available drives and partitions:"
    echo "-------------------------------------"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,PARTTYPE -p
    echo "-------------------------------------"
}

prompt_target_partition() {
    echo "Select a partition for Windows installation (e.g., /dev/sda3 or /dev/nvme0n1p3)"
    echo "[WARNING] All data on the selected partition will be erased."
    read -p "Enter partition path: " TARGET_PARTITION
    
    if [ -z "$TARGET_PARTITION" ]; then
        log_error "No partition specified"
        return 1
    fi
    
    echo "$TARGET_PARTITION"
    return 0
}

display_partition_details() {
    local partition="$1"
    local disk_path="$2"
    local part_num="$3"
    
    echo "Target partition details:"
    echo "-------------------------------------"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,PARTTYPE -p "$partition"
    echo "Disk: $disk_path, Partition: $part_num"
    echo "-------------------------------------"
}

validate_partition_comprehensive() {
    local partition="$1"
    local min_size_gb="${2:-$DEFAULT_MIN_SIZE_GB}"
    
    if ! validate_partition_exists "$partition"; then
        return 1
    fi
    
    if ! validate_partition_is_partition "$partition"; then
        return 1
    fi
    
    if ! validate_partition_not_efi "$partition"; then
        return 1
    fi
    
    if ! validate_partition_not_managed_volume "$partition"; then
        return 1
    fi
    
    if ! validate_partition_not_mounted_as_esp "$partition"; then
        return 1
    fi
    
    if ! validate_partition_not_system_partition "$partition"; then
        return 1
    fi
    
    if ! validate_partition_size "$partition" "$min_size_gb"; then
        return 1
    fi
    
    if ! validate_partition_not_mounted "$partition"; then
        return 1
    fi
    
    if ! validate_partition_permissions "$partition"; then
        return 1
    fi
    
    return 0
}
