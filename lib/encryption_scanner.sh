#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

validate_device_for_scanning() {
    local device="$1"
    
    if [ -z "$device" ]; then
        log_debug "Empty device path, skipping encryption scan"
        return 1
    fi
    
    if [ ! -e "$device" ]; then
        log_debug "Device does not exist: $device"
        return 1
    fi
    
    if [ ! -b "$device" ] && [ ! -d "$device" ]; then
        log_debug "Not a block device or directory: $device"
        return 1
    fi
    
    return 0
}

check_luks_encryption() {
    local partition="$1"
    
    if command -v cryptsetup >/dev/null 2>&1; then
        if cryptsetup isLuks "$partition" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

check_bitlocker_encryption() {
    local partition="$1"
    local btype="$2"
    
    if [ -n "${btype:-}" ] && echo "$btype" | grep -qi 'bitlocker'; then
        return 0
    elif blkid -p -o export "$partition" 2>/dev/null | grep -qi 'bitlocker'; then
        return 0
    fi
    return 1
}

check_managed_volume_type() {
    local fstype="$1"
    local ltype="$2"
    
    if [ -n "${fstype:-}" ]; then
        if [ "$fstype" = "lvm2_member" ] || [ "$fstype" = "linux_raid_member" ] || [ "$fstype" = "crypto_luks" ]; then
            echo "$fstype"
            return 0
        fi
    fi
    
    if [ -n "${ltype:-}" ] && [ "$ltype" = "crypt" ]; then
        echo "$ltype"
        return 0
    fi
    
    return 1
}

scan_partition_for_encryption() {
    local partition="$1"
    
    if [ ! -e "$partition" ]; then
        log_debug "Skipping non-existent partition: $partition"
        echo "NONE:0:"
        return 1
    fi
    
    local fstype=$(lsblk -no FSTYPE "$partition" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    local btype=$(blkid -s TYPE -o value "$partition" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    local ltype=$(lsblk -no TYPE "$partition" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    
    if check_luks_encryption "$partition"; then
        local finding=" - LUKS container detected on $partition"
        log_error "LUKS encryption detected on: $partition"
        echo "FOUND:$EXIT_ENC_LUKS:$finding"
        return 0
    fi
    
    if check_bitlocker_encryption "$partition" "$btype"; then
        local finding=" - BitLocker signature detected on $partition (blkid TYPE: $btype)"
        log_error "BitLocker encryption detected on: $partition"
        echo "FOUND:$EXIT_ENC_BITLOCKER:$finding"
        return 0
    fi
    
    local managed_type=$(check_managed_volume_type "$fstype" "$ltype")
    if [ $? -eq 0 ]; then
        local finding=" - Managed volume detected (filesystem type: ${managed_type}) on $partition"
        log_error "Managed volume detected on: $partition (type: $managed_type)"
        echo "FOUND:$EXIT_ENC_MANAGED:$finding"
        return 0
    fi
    
    echo "NONE:0:"
    return 1
}

encryption_scan_device() {
    local device="$1"
    
    if ! validate_device_for_scanning "$device"; then
        return 0
    fi

    local found_code=0
    local findings=""
    log_debug "Scanning device for encryption: $device"

    local children=$(lsblk -ln -o NAME,TYPE "$device" 2>/dev/null | awk '$2=="part"{print "/dev/"$1}')
    if [ -z "${children:-}" ]; then
        children="$device"
    fi

    for partition in $children; do
        local scan_result=$(scan_partition_for_encryption "$partition")
        local scan_status=$(echo "$scan_result" | cut -d: -f1)
        local scan_code=$(echo "$scan_result" | cut -d: -f2)
        local scan_finding=$(echo "$scan_result" | cut -d: -f3-)
        
        if [ "$scan_status" = "FOUND" ]; then
            if [ "$found_code" -eq 0 ]; then
                found_code=$scan_code
            fi
            findings="${findings}\n${scan_finding}"
        fi
    done

    if [ -n "${findings}" ]; then
        log_error "Encrypted or managed volume detected: $device"
        printf "%b\n" "$findings" >&2
        log_error "Operation aborted to prevent data loss. No writes were performed."
        return ${found_code:-$EXIT_ENC_MANAGED}
    fi

    log_debug "No encryption detected on device: $device"
    return 0
}

encryption_scan_partition() {
    local partition="$1"
    
    if [ -z "$partition" ]; then
        log_error "Partition path is empty"
        return 1
    fi
    
    if [ ! -b "$partition" ]; then
        log_error "Not a block device: $partition"
        return 1
    fi
    
    return $(encryption_scan_device "$partition")
}

encryption_scan_disk() {
    local disk="$1"
    
    if [ -z "$disk" ]; then
        log_error "Disk path is empty"
        return 1
    fi
    
    if [ ! -b "$disk" ]; then
        log_error "Not a block device: $disk"
        return 1
    fi
    
    return $(encryption_scan_device "$disk")
}
