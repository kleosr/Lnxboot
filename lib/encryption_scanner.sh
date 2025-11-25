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

encryption_scan_device() {
    local device="$1"
    
    if ! validate_device_for_scanning "$device"; then
        return 0
    fi

    local children found_code fstype btype ltype findings
    found_code=0
    findings=""

    log_debug "Scanning device for encryption: $device"

    children=$(lsblk -ln -o NAME,TYPE "$device" 2>/dev/null | awk '$2=="part"{print "/dev/"$1}')
    if [ -z "${children:-}" ]; then
        children="$device"
    fi

    for p in $children; do
        if [ ! -e "$p" ]; then
            log_debug "Skipping non-existent partition: $p"
            continue
        fi
        
        fstype=$(lsblk -no FSTYPE "$p" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
        btype=$(blkid -s TYPE -o value "$p" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
        ltype=$(lsblk -no TYPE "$p" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")

        if command -v cryptsetup >/dev/null 2>&1; then
            if cryptsetup isLuks "$p" >/dev/null 2>&1; then
                findings="${findings}\n - LUKS container detected on $p"
                if [ $found_code -eq 0 ]; then
                    found_code=$EXIT_ENC_LUKS
                fi
                log_error "LUKS encryption detected on: $p"
                continue
            fi
        else
            log_debug "cryptsetup not available, skipping LUKS detection"
        fi

        if [ -n "${btype:-}" ] && echo "$btype" | grep -qi 'bitlocker'; then
            findings="${findings}\n - BitLocker signature detected on $p (blkid TYPE: $btype)"
            if [ $found_code -eq 0 ]; then
                found_code=$EXIT_ENC_BITLOCKER
            fi
            log_error "BitLocker encryption detected on: $p"
        elif blkid -p -o export "$p" 2>/dev/null | grep -qi 'bitlocker'; then
            findings="${findings}\n - BitLocker metadata detected on $p"
            if [ $found_code -eq 0 ]; then
                found_code=$EXIT_ENC_BITLOCKER
            fi
            log_error "BitLocker encryption detected on: $p"
        fi

        if [ -n "${fstype:-}" ]; then
            if [ "$fstype" = "lvm2_member" ] || [ "$fstype" = "linux_raid_member" ] || [ "$fstype" = "crypto_luks" ]; then
                findings="${findings}\n - Managed volume detected (filesystem type: ${fstype}) on $p"
                if [ $found_code -eq 0 ]; then
                    found_code=$EXIT_ENC_MANAGED
                fi
                log_error "Managed volume detected on: $p (type: $fstype)"
            fi
        fi
        
        if [ -n "${ltype:-}" ] && [ "$ltype" = "crypt" ]; then
            findings="${findings}\n - Encrypted device detected (device type: ${ltype}) on $p"
            if [ $found_code -eq 0 ]; then
                found_code=$EXIT_ENC_MANAGED
            fi
            log_error "Encrypted device detected on: $p (type: $ltype)"
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
