#!/bin/bash

# =========================================
# Universal Linux Windows Dual-Boot Setup Utility
# Supports multiple package managers and distributions
# Creates a bootable Windows installation environment from a Windows ISO
# =========================================

# Exit immediately if a command exits with a non-zero status
set -e

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
    local pkg_manager=$(detect_package_manager)
    local grub_config_path
    local grub_cmd
    local grub_custom_path
    
    case $pkg_manager in
        "rpm-ostree"|"dnf"|"yum")
            grub_config_path="/boot/grub2/grub.cfg"
            grub_custom_path="/etc/grub.d/40_custom"
            grub_cmd="grub2-mkconfig"
            ;;
        "apt")
            grub_config_path="/boot/grub/grub.cfg"
            grub_custom_path="/etc/grub.d/40_custom"
            if command -v update-grub >/dev/null 2>&1; then
                grub_cmd="update-grub"
            else
                grub_cmd="grub-mkconfig"
            fi
            ;;
        "pacman"|"zypper")
            if [ -d "/boot/grub" ]; then
                grub_config_path="/boot/grub/grub.cfg"
            else
                grub_config_path="/boot/grub2/grub.cfg"
            fi
            grub_custom_path="/etc/grub.d/40_custom"
            if command -v grub-mkconfig >/dev/null 2>&1; then
                grub_cmd="grub-mkconfig"
            elif command -v grub2-mkconfig >/dev/null 2>&1; then
                grub_cmd="grub2-mkconfig"
            else
                echo "[ERROR] No GRUB configuration command found."
                exit 1
            fi
            ;;
    esac
    
    echo "$grub_config_path:$grub_cmd:$grub_custom_path"
}

# Check for required tools
check_requirements() {
    # Check for ntfs-3g
    if ! command -v mkfs.ntfs >/dev/null 2>&1; then
        echo "[INFO] Installing required packages..."
        install_packages
    fi
    
    # Check for GRUB tools
    if ! command -v grub2-mkconfig >/dev/null 2>&1 && ! command -v grub-mkconfig >/dev/null 2>&1 && ! command -v update-grub >/dev/null 2>&1; then
        echo "[INFO] Installing required packages..."
        install_packages
    fi
    
    # Check for efibootmgr if UEFI
    if [ "$(detect_boot_mode)" = "UEFI" ] && ! command -v efibootmgr >/dev/null 2>&1; then
        echo "[INFO] Installing required packages..."
        install_packages
    fi
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

# Get partition details
PART_SIZE=$(lsblk -b -n -o SIZE "$TARGET_PARTITION" | head -n1)
PART_NAME=$(basename "$TARGET_PARTITION")

# Handle both SATA and NVMe drives for GRUB configuration
if [[ "$PART_NAME" == nvme* ]]; then
    # NVMe format: nvme0n1p1 -> Extract disk and partition number
    DISK_NAME=$(echo "$PART_NAME" | sed -r 's/p[0-9]+$//')
    PART_NUM=$(echo "$PART_NAME" | grep -o 'p[0-9]\+$' | grep -o '[0-9]\+')
    DISK_PATH="/dev/$DISK_NAME"
else
    # SATA format: sda1 -> Extract disk and partition number
    DISK_NAME=$(echo "$PART_NAME" | sed 's/[0-9]//g')
    PART_NUM=$(echo "$PART_NAME" | sed 's/[^0-9]//g')
    DISK_PATH="/dev/$DISK_NAME"
fi

echo "Target partition details:"
echo "-------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,PARTTYPE -p "$TARGET_PARTITION"
echo "Disk: $DISK_PATH, Partition: $PART_NUM"
echo "-------------------------------------"

# Check partition size (minimum 20GB for Windows)
MIN_SIZE=$((20 * 1024 * 1024 * 1024))  # 20GB in bytes
if [ "$PART_SIZE" -lt "$MIN_SIZE" ]; then
    echo "[ERROR] Partition too small. Windows requires at least 20GB."
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

# Format partition as NTFS
log "Formatting $TARGET_PARTITION as NTFS"
umount "$TARGET_PARTITION" 2>/dev/null || true
echo "[INFO] Formatting partition..."
mkfs.ntfs -f -L "Windows" "$TARGET_PARTITION" || {
    echo "[ERROR] Failed to format partition as NTFS."
    echo "Please install ntfs-3g package and try again."
    exit 1
}

# Mount the Windows ISO
log "Mounting Windows ISO"
mount -o loop "$ISO_PATH" "$ISO_MOUNT" || {
    echo "[ERROR] Failed to mount ISO. Please verify the ISO file is valid."
    exit 1
}

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
    rsync -av --progress "$ISO_MOUNT"/ "$MOUNT_POINT"/ || {
        echo "[ERROR] Failed to copy Windows files. Check available disk space."
        exit 1
    }
else
    cp -r "$ISO_MOUNT"/* "$MOUNT_POINT"/ || {
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
PART_UUID=$(blkid -s UUID -o value "$TARGET_PARTITION")

# Create GRUB menu entry for Windows
log "Creating GRUB menu entry for Windows"

if [ "$BOOT_MODE" = "UEFI" ]; then
    # UEFI boot entry
    cat << EOF >> "$GRUB_CUSTOM_FILE"

# Windows Boot Entry - Added by Lnxboot
menuentry "Windows Installation (UEFI)" {
    insmod part_gpt
    insmod part_msdos
    insmod ntfs
    insmod fat
    insmod chain
    search --fs-uuid --set=root $PART_UUID
    if [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    elif [ -f /bootmgr.efi ]; then
        chainloader /bootmgr.efi
    elif [ -f /EFI/Boot/bootx64.efi ]; then
        chainloader /EFI/Boot/bootx64.efi
    else
        chainloader /bootmgr
    fi
}
EOF
else
    # Legacy BIOS boot entry
    cat << EOF >> "$GRUB_CUSTOM_FILE"

# Windows Boot Entry - Added by Lnxboot  
menuentry "Windows Installation (Legacy)" {
    insmod part_msdos
    insmod part_gpt
    insmod ntfs
    insmod chain
    search --fs-uuid --set=root $PART_UUID
    drivemap -s (hd0) \${root}
    chainloader +1
}
EOF
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

# For UEFI systems, also try to add Windows to EFI boot manager
if [ "$BOOT_MODE" = "UEFI" ] && command -v efibootmgr >/dev/null 2>&1; then
    log "Adding Windows to EFI boot manager"
    EFI_PART=$(find_efi_partition)
    if [ -n "$EFI_PART" ]; then
        # Try to add Windows boot entry
        efibootmgr -c -d "$DISK_PATH" -p "$PART_NUM" -L "Windows Boot Manager" -l "\\EFI\\Microsoft\\Boot\\bootmgfw.efi" 2>/dev/null || true
    fi
fi

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
echo "- If Windows doesn't boot, try running: sudo $GRUB_CMD -o $GRUB_CFG_FILE"
echo "- For UEFI systems, Windows should appear in your firmware boot menu"
echo "- After Windows installation, you may need to restore GRUB bootloader"
echo "- A log file of this installation is available at $LOG_FILE"
echo
echo "System is ready for reboot."
