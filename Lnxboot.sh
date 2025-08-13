#!/bin/bash

# =========================================
# Universal Linux Windows Dual-Boot Setup Utility
# Supports multiple package managers and distributions
# Creates a bootable Windows installation environment from a Windows ISO
# =========================================

# Exit immediately on errors, unset variables, and failed pipes; propagate ERR trap
set -Eeuo pipefail

# Verify script is run with root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "[ERROR] This script requires root privileges."
    echo "Usage: sudo $0 /path/to/windows.iso"
    exit 1
fi

# Function to detect package manager and install packages
detect_package_manager() {
    if command -v rpm-ostree >/dev/null 2>&1; then
        echo "rpm-ostree"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Function to install required packages
install_packages() {
    local pkg_manager=$(detect_package_manager)
    
    case $pkg_manager in
        "rpm-ostree")
            rpm-ostree install ntfs-3g grub2-tools grub2-efi-x64 efibootmgr
            echo "[INFO] Packages installed. Please reboot and run the script again."
            exit 0
            ;;
        "apt")
            apt-get update
            apt-get install -y ntfs-3g grub-common grub-efi-amd64 efibootmgr
            ;;
        "dnf"|"yum")
            $pkg_manager install -y ntfs-3g grub2-tools grub2-efi-x64 efibootmgr
            ;;
        "pacman")
            pacman -Sy --noconfirm ntfs-3g grub efibootmgr
            ;;
        "zypper")
            zypper install -y ntfs-3g grub2 grub2-x86_64-efi efibootmgr
            ;;
        *)
            echo "[ERROR] Unsupported package manager. Please install required packages manually:"
            echo "- ntfs-3g"
            echo "- grub2-tools or grub-common"
            echo "- grub2-efi-x64 or grub-efi-amd64"
            echo "- efibootmgr"
            exit 1
            ;;
    esac
}

# Function to detect boot mode (UEFI or Legacy)
detect_boot_mode() {
    if [ -d "/sys/firmware/efi" ]; then
        echo "UEFI"
    else
        echo "Legacy"
    fi
}

# Function to find EFI system partition
find_efi_partition() {
    # Look for EFI system partition
    local efi_part=$(lsblk -f | grep -i "fat32\|vfat" | grep -E "/boot/efi|/efi" | awk '{print $1}' | head -1)
    if [ -z "$efi_part" ]; then
        # Alternative method
        efi_part=$(fdisk -l 2>/dev/null | grep "EFI System" | awk '{print $1}' | head -1)
    fi
    echo "$efi_part"
}

# Function to detect and configure GRUB
configure_grub() {
    local grub_config_path=""
    local grub_cmd=""
    local grub_custom_path="/etc/grub.d/40_custom"

    # Determine config output path
    if [ -d "/boot/grub" ]; then
        grub_config_path="/boot/grub/grub.cfg"
    elif [ -d "/boot/grub2" ]; then
        grub_config_path="/boot/grub2/grub.cfg"
    else
        # Fallback: prefer /boot/grub
        grub_config_path="/boot/grub/grub.cfg"
    fi

    # Determine the command to regenerate GRUB config
    if command -v update-grub >/dev/null 2>&1; then
        grub_cmd="update-grub"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub_cmd="grub-mkconfig"
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub_cmd="grub2-mkconfig"
    else
        echo "[ERROR] No GRUB configuration command found."
        exit 1
    fi

    echo "$grub_config_path:$grub_cmd:$grub_custom_path"
}

# Check for required tools
check_requirements() {
    # Check for ntfs-3g formatter (mkfs.ntfs or mkntfs)
    if ! command -v mkfs.ntfs >/dev/null 2>&1 && ! command -v mkntfs >/dev/null 2>&1; then
        echo "[INFO] Installing required packages..."
        install_packages
    fi
    
    # Check for GRUB tools
    if ! command -v grub2-mkconfig >/dev/null 2>&1 && ! command -v grub-mkconfig >/dev/null 2>&1 && ! command -v update-grub >/dev/null 2>&1; then
        echo "[INFO] Installing required packages..."
        install_packages
    fi
    
    # efibootmgr is optional; not required for this flow
}

# Run requirements check
check_requirements

# Check for ISO path argument
if [ -z "$1" ]; then
    echo "[ERROR] No Windows ISO path provided."
    echo "Usage: $0 /path/to/windows.iso"
    echo "Please provide a valid Windows ISO file path."
    exit 1
fi

ISO_PATH="$1"
MOUNT_POINT="/mnt/windows_target"
ISO_MOUNT="/mnt/iso_temp"
LOG_FILE="/var/log/lnxboot.log"
BOOT_MODE=$(detect_boot_mode)

# Function for logging
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

# Initialize logging file with secure permissions
mkdir -p "$(dirname "$LOG_FILE")"
umask 077
touch "$LOG_FILE"

# Error trap for better diagnostics
on_error() {
    local exit_code=$?
    local line_no=${BASH_LINENO[0]:-0}
    log "ERROR: Command failed with exit code $exit_code at line $line_no: $BASH_COMMAND"
}
trap on_error ERR

# Function to clean up on exit
cleanup() {
    log "Cleaning up mount points..."
    umount "$ISO_MOUNT" 2>/dev/null || true
    umount "$MOUNT_POINT" 2>/dev/null || true
    rm -rf "$ISO_MOUNT" "$MOUNT_POINT" 2>/dev/null || true
    log "Cleanup completed."
}

# Set trap for cleanup on script exit
trap cleanup EXIT

log "Starting Windows dual-boot setup (Boot mode: $BOOT_MODE)"

# Verify ISO exists
if [ ! -f "$ISO_PATH" ]; then
    echo "[ERROR] Windows ISO not found: $ISO_PATH"
    exit 1
fi

# Display available drives and partitions
echo "Available drives and partitions:"
echo "-------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,PARTTYPE -p
echo "-------------------------------------"

# Get target partition from user
echo "Select a partition for Windows installation (e.g., /dev/sda3 or /dev/nvme0n1p3)"
echo "[WARNING] All data on the selected partition will be erased."
read -p "Enter partition path: " TARGET_PARTITION

# Validate partition exists
if ! lsblk "$TARGET_PARTITION" >/dev/null 2>&1; then
    echo "[ERROR] Invalid partition: $TARGET_PARTITION"
    echo "Please verify the partition path and try again."
    exit 1
fi

# Disallow empty input
if [ -z "${TARGET_PARTITION:-}" ]; then
    echo "[ERROR] No partition specified."
    exit 1
fi

# Ensure the selected target is a partition (not a whole disk)
if [ "$(lsblk -no TYPE "$TARGET_PARTITION")" != "part" ]; then
    echo "[ERROR] Target must be a partition (e.g., /dev/sda3), not a whole disk."
    exit 1
fi

# Prevent selecting the EFI System Partition as target
EFI_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
PART_TYPE=$(lsblk -no PARTTYPE "$TARGET_PARTITION" | tr '[:upper:]' '[:lower:]' || true)
if [ "$PART_TYPE" = "$EFI_GUID" ]; then
    echo "[ERROR] The selected partition appears to be the EFI System Partition. Choose a different partition."
    exit 1
fi

# Get partition details
PART_SIZE=$(lsblk -b -n -o SIZE "$TARGET_PARTITION" | head -n1)
DISK_NAME=$(lsblk -no pkname "$TARGET_PARTITION")
DISK_PATH="/dev/$DISK_NAME"
PART_NUM=$(lsblk -no PARTNUM "$TARGET_PARTITION" | head -n1 || echo "")
PART_NAME=$(basename "$TARGET_PARTITION")

echo "Target partition details:"
echo "-------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,PARTTYPE -p "$TARGET_PARTITION"
echo "Disk: $DISK_PATH, Partition: $PART_NUM"
echo "-------------------------------------"

# Check partition size (minimum configurable, default 32GB for modern Windows)
MIN_SIZE_GB=${MIN_SIZE_GB:-32}
MIN_SIZE=$((MIN_SIZE_GB * 1024 * 1024 * 1024))
if [ "$PART_SIZE" -lt "$MIN_SIZE" ]; then
    echo "[ERROR] Partition too small. Windows typically requires at least ${MIN_SIZE_GB}GB."
    echo "Current size: $(( PART_SIZE / 1024 / 1024 / 1024 )) GB"
    exit 1
fi

# Confirm with user before proceeding
echo "[WARNING] This will erase all data on $TARGET_PARTITION"
read -p "Do you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

log "Preparing to install Windows from $ISO_PATH to $TARGET_PARTITION"

# Create and clean mount points
log "Creating mount points"
rm -rf "$MOUNT_POINT" "$ISO_MOUNT" 2>/dev/null || true
mkdir -p "$MOUNT_POINT" "$ISO_MOUNT"

# Ensure target partition is not mounted (prevent formatting active mounts)
CURRENT_MOUNTPOINT=$(lsblk -no MOUNTPOINT "$TARGET_PARTITION" | head -n1 || true)
if [ -n "${CURRENT_MOUNTPOINT:-}" ]; then
    echo "[ERROR] Target partition is currently mounted at $CURRENT_MOUNTPOINT. Please unmount it and try again."
    exit 1
fi

# Format partition as NTFS
log "Formatting $TARGET_PARTITION as NTFS"
umount "$TARGET_PARTITION" 2>/dev/null || true
echo "[INFO] Formatting partition..."
if command -v mkfs.ntfs >/dev/null 2>&1; then
    mkfs.ntfs -f -L "Windows" "$TARGET_PARTITION" || {
        echo "[ERROR] Failed to format partition as NTFS."
        echo "Please install ntfs-3g package and try again."
        exit 1
    }
else
    mkntfs -f -L "Windows" "$TARGET_PARTITION" || {
        echo "[ERROR] Failed to format partition as NTFS."
        echo "Please install ntfs-3g package and try again."
        exit 1
    }
fi
sync
sleep 1

# Mount the Windows ISO
log "Mounting Windows ISO"
mount -o loop,ro "$ISO_PATH" "$ISO_MOUNT" || {
    echo "[ERROR] Failed to mount ISO. Please verify the ISO file is valid."
    exit 1
}

# Validate ISO looks like a Windows installer
if [ ! -e "$ISO_MOUNT/sources/boot.wim" ] && [ ! -e "$ISO_MOUNT/sources/install.wim" ]; then
    echo "[ERROR] The mounted ISO does not appear to be a Windows installation image (missing sources/boot.wim)."
    exit 1
fi

# Ensure ISO contents will fit on the target partition (basic check)
REQUIRED_BYTES=$(du -sb "$ISO_MOUNT" | awk '{print $1}')
SAFETY_MARGIN=$((1024 * 1024 * 1024))
if [ $((REQUIRED_BYTES + SAFETY_MARGIN)) -gt "$PART_SIZE" ]; then
    echo "[ERROR] Target partition is too small for the contents of the Windows ISO."
    echo "Required (approx): $(( (REQUIRED_BYTES + SAFETY_MARGIN) / 1024 / 1024 / 1024 )) GB"
    echo "Available: $(( PART_SIZE / 1024 / 1024 / 1024 )) GB"
    exit 1
fi

# Mount target partition
log "Mounting target partition"
mount "$TARGET_PARTITION" "$MOUNT_POINT" || {
    echo "[ERROR] Failed to mount the target partition."
    exit 1
}

# Copy Windows files
log "Copying Windows installation files (this may take several minutes)"
echo "Copying files from Windows ISO to the target partition..."

# Use rsync for better progress and error handling
if command -v rsync >/dev/null 2>&1; then
    rsync -a --info=progress2 "$ISO_MOUNT"/ "$MOUNT_POINT"/ || {
        echo "[ERROR] Failed to copy Windows files. Check available disk space."
        exit 1
    }
else
    cp -a "$ISO_MOUNT"/. "$MOUNT_POINT"/ || {
        echo "[ERROR] Failed to copy Windows files. Check available disk space."
        exit 1
    }
fi

# Ensure proper sync of filesystem
sync

# Unmount filesystems properly
log "Unmounting filesystems"
umount "$ISO_MOUNT" || log "Warning: Could not unmount ISO"
umount "$MOUNT_POINT" || log "Warning: Could not unmount target partition"

# Configure GRUB based on distribution
IFS=':' read -r GRUB_CFG_FILE GRUB_CMD GRUB_CUSTOM_FILE <<< "$(configure_grub)"

# Get partition UUID for GRUB entry
PART_UUID=$(blkid -s UUID -o value "$TARGET_PARTITION" || true)
if [ -z "${PART_UUID:-}" ]; then
    echo "[ERROR] Failed to retrieve partition UUID for $TARGET_PARTITION."
    exit 1
fi

# Create GRUB menu entry for Windows (idempotent)
log "Creating GRUB menu entry for Windows"
mkdir -p "$(dirname "$GRUB_CUSTOM_FILE")"

# Ensure 40_custom has the standard header if it doesn't exist
if [ ! -f "$GRUB_CUSTOM_FILE" ]; then
    cat > "$GRUB_CUSTOM_FILE" << 'EOF_GRUBCUST'
#!/bin/sh
exec tail -n +3 $0
# Custom GRUB menu entries
EOF_GRUBCUST
    chmod +x "$GRUB_CUSTOM_FILE"
fi

if ! grep -q "$PART_UUID" "$GRUB_CUSTOM_FILE"; then
    if [ "$BOOT_MODE" = "UEFI" ]; then
        # UEFI boot entry: chainload Windows EFI loader from the NTFS partition via GRUB
        cat << EOF >> "$GRUB_CUSTOM_FILE"

# Windows Boot Entry - Added by Lnxboot (UEFI)
menuentry "Windows Installation (UEFI)" {
    insmod part_gpt
    insmod part_msdos
    insmod ntfs
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $PART_UUID
    if [ -f /EFI/Boot/bootx64.efi ]; then
        chainloader /EFI/Boot/bootx64.efi
    elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    elif [ -f /bootmgr.efi ]; then
        chainloader /bootmgr.efi
    else
        chainloader /bootmgr
    fi
}
EOF
    else
        # Legacy BIOS boot entry: prefer ntldr module to load bootmgr, fallback to chainloader +1
        cat << EOF >> "$GRUB_CUSTOM_FILE"

# Windows Boot Entry - Added by Lnxboot (Legacy BIOS)
menuentry "Windows Installation (Legacy)" {
    insmod part_msdos
    insmod part_gpt
    insmod ntfs
    insmod ntldr
    insmod chain
    search --no-floppy --fs-uuid --set=root $PART_UUID
    if [ -f /bootmgr ]; then
        ntldr /bootmgr
    else
        chainloader +1
    fi
}
EOF
    fi
else
    log "GRUB custom entry already contains this partition UUID. Skipping entry creation."
fi

# Defensive check for GRUB variables
if [ -z "${GRUB_CMD:-}" ] || [ -z "${GRUB_CFG_FILE:-}" ] || [ -z "${GRUB_CUSTOM_FILE:-}" ]; then
    echo "[ERROR] Unable to determine GRUB configuration command or paths."
    exit 1
fi

# Update GRUB configuration
log "Updating GRUB configuration"
case "$GRUB_CMD" in
    "update-grub")
        update-grub || {
            echo "[ERROR] Failed to update GRUB configuration."
            exit 1
        }
        ;;
    "grub-mkconfig")
        grub-mkconfig -o "$GRUB_CFG_FILE" || {
            echo "[ERROR] Failed to update GRUB configuration."
            exit 1
        }
        ;;
    "grub2-mkconfig")
        grub2-mkconfig -o "$GRUB_CFG_FILE" || {
            echo "[ERROR] Failed to update GRUB configuration."
            exit 1
        }
        ;;
esac


# Display completion information
echo
echo "Windows dual-boot setup completed successfully."
echo "============================================="
echo "Boot Mode: $BOOT_MODE"
echo "Target Partition: $TARGET_PARTITION"
echo "Partition UUID: $PART_UUID"
echo "Partition Size: $(( PART_SIZE / 1024 / 1024 / 1024 )) GB"
echo "GRUB Configuration: $GRUB_CFG_FILE"
echo
echo "Boot Instructions:"
echo "1. Restart your system"
echo "2. Select 'Windows Installation' from the GRUB boot menu"
echo "3. Follow the Windows installation wizard"
echo "4. When prompted for installation location, select the partition you prepared"
echo "   (Look for the partition labeled 'Windows' with ~$(( PART_SIZE / 1024 / 1024 / 1024 ))GB)"
echo
echo "Current partition status:"
echo "-------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,UUID -p "$TARGET_PARTITION"
echo

# Final notes
echo "Important Notes:"
echo "- Ensure Secure Boot is disabled in BIOS/UEFI settings before installation"
if [ "$GRUB_CMD" = "update-grub" ]; then
    echo "- If Windows doesn't boot, try running: sudo update-grub"
elif [ "$GRUB_CMD" = "grub-mkconfig" ]; then
    echo "- If Windows doesn't boot, try running: sudo grub-mkconfig -o $GRUB_CFG_FILE"
elif [ "$GRUB_CMD" = "grub2-mkconfig" ]; then
    echo "- If Windows doesn't boot, try running: sudo grub2-mkconfig -o $GRUB_CFG_FILE"
fi
echo "- For UEFI systems, Windows should appear in your firmware boot menu"
echo "- After Windows installation, you may need to restore GRUB bootloader"
echo "- A log file of this installation is available at $LOG_FILE"
echo
echo "System is ready for reboot."
