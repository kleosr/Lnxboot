#!/bin/bash

detect_boot_mode() {
    if [ -d "/sys/firmware/efi" ]; then
        echo "UEFI"
    else
        echo "Legacy"
    fi
}

find_efi_partition() {
    local efi_part=$(lsblk -f | grep -i "fat32\|vfat" | grep -E "/boot/efi|/efi" | awk '{print $1}' | head -1)
    if [ -z "$efi_part" ]; then
        efi_part=$(fdisk -l 2>/dev/null | grep "EFI System" | awk '{print $1}' | head -1)
    fi
    echo "$efi_part"
}

