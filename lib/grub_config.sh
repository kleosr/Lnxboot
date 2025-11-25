#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

validate_grub_directory() {
    local grub_dir="$1"
    
    if [ ! -d "$grub_dir" ]; then
        log_error "GRUB directory does not exist: $grub_dir"
        return 1
    fi
    
    if [ ! -r "$grub_dir" ]; then
        log_error "GRUB directory is not readable: $grub_dir"
        return 1
    fi
    
    return 0
}

validate_grub_file_permissions() {
    local file_path="$1"
    local description="${2:-GRUB file}"
    
    if [ -z "$file_path" ]; then
        log_error "$description path is empty"
        return 1
    fi
    
    local dir_path=$(dirname "$file_path")
    
    if [ ! -d "$dir_path" ]; then
        if ! mkdir -p "$dir_path" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Cannot create directory for $description: $dir_path"
            return 1
        fi
    fi
    
    if [ ! -w "$dir_path" ]; then
        log_error "Directory is not writable for $description: $dir_path"
        return 1
    fi
    
    if [ -f "$file_path" ] && [ ! -w "$file_path" ]; then
        log_error "$description is not writable: $file_path"
        return 1
    fi
    
    return 0
}

configure_grub() {
    local grub_config_path=""
    local grub_cmd=""
    
    if [ -d "/boot/grub" ]; then
        if ! validate_grub_directory "/boot/grub"; then
            return 1
        fi
        grub_config_path="$GRUB_CONFIG_PATH_PRIMARY"
    elif [ -d "/boot/grub2" ]; then
        if ! validate_grub_directory "/boot/grub2"; then
            return 1
        fi
        grub_config_path="$GRUB_CONFIG_PATH_SECONDARY"
    else
        log_warn "GRUB directory not found, using default: $GRUB_CONFIG_PATH_PRIMARY"
        grub_config_path="$GRUB_CONFIG_PATH_PRIMARY"
    fi
    
    if command -v update-grub >/dev/null 2>&1; then
        grub_cmd="update-grub"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub_cmd="grub-mkconfig"
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub_cmd="grub2-mkconfig"
    else
        log_error "No GRUB configuration command found"
        return 1
    fi
    
    if ! validate_grub_file_permissions "$GRUB_CUSTOM_FILE" "GRUB custom file"; then
        return 1
    fi
    
    echo "$grub_config_path:$grub_cmd:$GRUB_CUSTOM_FILE"
    return 0
}

validate_grub_entry_params() {
    local partition_uuid="$1"
    local boot_mode="$2"
    local grub_custom_file="$3"
    
    if [ -z "$partition_uuid" ]; then
        log_error "Partition UUID is empty"
        return 1
    fi
    
    if [ -z "$boot_mode" ]; then
        log_error "Boot mode is empty"
        return 1
    fi
    
    if [ -z "$grub_custom_file" ]; then
        log_error "GRUB custom file path is empty"
        return 1
    fi
    
    if ! validate_grub_file_permissions "$grub_custom_file" "GRUB custom file"; then
        return 1
    fi
    
    return 0
}

check_grub_entry_exists() {
    local grub_custom_file="$1"
    local partition_uuid="$2"
    
    if [ -f "$grub_custom_file" ] && grep -q "$partition_uuid" "$grub_custom_file" 2>/dev/null; then
        log_info "GRUB entry already exists for partition UUID: $partition_uuid"
        return 0
    fi
    return 1
}

initialize_grub_custom_file() {
    local grub_custom_file="$1"
    
    if [ -f "$grub_custom_file" ]; then
        return 0
    fi
    
    local grub_dir=$(dirname "$grub_custom_file")
    if ! mkdir -p "$grub_dir" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to create GRUB directory: $grub_dir"
        return 1
    fi
    
        if ! cat > "$grub_custom_file" << EOF_GRUBCUST
#!/bin/sh
exec tail -n +${GRUB_CUSTOM_FILE_HEADER_LINES} \$0
EOF_GRUBCUST
    then
        log_error "Failed to create GRUB custom file: $grub_custom_file"
        return 1
    fi
    
    if ! chmod +x "$grub_custom_file" 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "Failed to make GRUB custom file executable: $grub_custom_file"
    fi
    
    return 0
}

create_uefi_grub_entry() {
    local grub_custom_file="$1"
    local partition_uuid="$2"
    
    if ! cat >> "$grub_custom_file" << EOF

menuentry "Windows Installation (UEFI)" {
    insmod part_gpt
    insmod part_msdos
    insmod ntfs
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $partition_uuid
    if [ -f /EFI/Boot/bootx64.efi ]; then
        chainloader /EFI/Boot/bootx64.efi
    elif [ -f /EFI/Boot/bootaa64.efi ]; then
        chainloader /EFI/Boot/bootaa64.efi
    elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    elif [ -f /bootmgr.efi ]; then
        chainloader /bootmgr.efi
    else
        chainloader /bootmgr
    fi
}
EOF
    then
        log_error "Failed to append UEFI GRUB entry"
        return 1
    fi
    return 0
}

create_legacy_grub_entry() {
    local grub_custom_file="$1"
    local partition_uuid="$2"
    
    if ! cat >> "$grub_custom_file" << EOF

menuentry "Windows Installation (Legacy)" {
    insmod part_msdos
    insmod part_gpt
    insmod ntfs
    insmod chain
    search --no-floppy --fs-uuid --set=root $partition_uuid
    if [ -f /bootmgr ]; then
        if ! chainloader /bootmgr 2>/dev/null; then
            insmod ntldr
            ntldr /bootmgr
        fi
    else
        echo "bootmgr not found"
        sleep ${GRUB_BOOTMGR_ERROR_SLEEP_SEC}
        return
    fi
}
EOF
    then
        log_error "Failed to append Legacy BIOS GRUB entry"
        return 1
    fi
    return 0
}

create_grub_entry() {
    local partition_uuid="$1"
    local boot_mode="$2"
    local grub_custom_file="$3"
    
    if ! validate_grub_entry_params "$partition_uuid" "$boot_mode" "$grub_custom_file"; then
        return 1
    fi
    
    if check_grub_entry_exists "$grub_custom_file" "$partition_uuid"; then
        return 0
    fi
    
    if ! initialize_grub_custom_file "$grub_custom_file"; then
        return 1
    fi
    
    if [ "$boot_mode" = "UEFI" ]; then
        if ! create_uefi_grub_entry "$grub_custom_file" "$partition_uuid"; then
            return 1
        fi
    else
        if ! create_legacy_grub_entry "$grub_custom_file" "$partition_uuid"; then
            return 1
        fi
    fi
    
    log_info "GRUB entry created successfully for partition UUID: $partition_uuid"
    return 0
}

update_grub_config() {
    local grub_cmd="$1"
    local grub_cfg_file="$2"
    
    if [ -z "$grub_cmd" ] || [ -z "$grub_cfg_file" ]; then
        log_error "GRUB command or config file path is empty"
        return 1
    fi
    
    local grub_cfg_dir=$(dirname "$grub_cfg_file")
    if [ ! -d "$grub_cfg_dir" ]; then
        log_error "GRUB config directory does not exist: $grub_cfg_dir"
        return 1
    fi
    
    if [ ! -w "$grub_cfg_dir" ]; then
        log_error "GRUB config directory is not writable: $grub_cfg_dir"
        return 1
    fi
    
    case "$grub_cmd" in
        "update-grub")
            if ! update-grub 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to update GRUB configuration with update-grub"
                return 1
            fi
            ;;
        "grub-mkconfig")
            if ! grub-mkconfig -o "$grub_cfg_file" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to update GRUB configuration with grub-mkconfig"
                return 1
            fi
            ;;
        "grub2-mkconfig")
            if ! grub2-mkconfig -o "$grub_cfg_file" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to update GRUB configuration with grub2-mkconfig"
                return 1
            fi
            ;;
        *)
            log_error "Unknown GRUB command: $grub_cmd"
            return 1
            ;;
    esac
    
    if [ ! -f "$grub_cfg_file" ]; then
        log_warn "GRUB config file was not created: $grub_cfg_file"
    fi
    
    log_info "GRUB configuration updated successfully"
    return 0
}

get_partition_uuid() {
    local partition="$1"
    
    if [ -z "$partition" ]; then
        log_error "Partition path is empty"
        return 1
    fi
    
    if [ ! -b "$partition" ]; then
        log_error "Not a block device: $partition"
        return 1
    fi
    
    local uuid=$(blkid -s UUID -o value "$partition" 2>/dev/null || echo "")
    
    if [ -z "$uuid" ]; then
        log_error "Cannot retrieve UUID for partition: $partition"
        return 1
    fi
    
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        log_warn "Partition UUID format may be invalid: $uuid"
    fi
    
    echo "$uuid"
    return 0
}
