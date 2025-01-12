#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if ISO path is provided
if [ -z "$1" ]; then
    echo "Please provide the path to Windows ISO"
    echo "Usage: $0 /path/to/windows.iso"
    exit 1
fi

ISO_PATH="$1"
MOUNT_POINT="/mnt/windows_iso_temp"
ISO_MOUNT="/mnt/iso_temp"

# Show available partitions
echo "Available partitions:"
echo "----------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p | grep "sd[a-z][0-9]"
echo "----------------------------------------"

# Ask user to select partition
echo "Enter the partition name where you want to install Windows (e.g., /dev/sda3):"
read -p "Partition: " TARGET_PARTITION

# Verify the partition exists
if ! lsblk "$TARGET_PARTITION" >/dev/null 2>&1; then
    echo "Error: Partition $TARGET_PARTITION not found!"
    exit 1
fi

# Get partition information
PART_SIZE=$(lsblk -b -n -o SIZE "$TARGET_PARTITION" | head -n1)
PART_NAME=$(basename "$TARGET_PARTITION")
DISK_NAME=$(echo "$PART_NAME" | sed 's/[0-9]//g')
PART_NUM=$(echo "$PART_NAME" | sed 's/[^0-9]//g')

echo "Selected partition details:"
echo "----------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p "$TARGET_PARTITION"
echo "----------------------------------------"

# Confirm with user
read -p "Are you sure you want to use this partition? This will erase all data on it. (y/N): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Check if ISO exists
if [ ! -f "$ISO_PATH" ]; then
    echo "ISO file not found: $ISO_PATH"
    exit 1
fi

# Create mount points
echo "Creating mount points..."
mkdir -p "$MOUNT_POINT" "$ISO_MOUNT"

# Mount the ISO
echo "Mounting ISO..."
mount -o loop "$ISO_PATH" "$ISO_MOUNT"

# Mount the target partition
echo "Mounting target partition..."
umount "$TARGET_PARTITION" 2>/dev/null || true
mount "$TARGET_PARTITION" "$MOUNT_POINT"

# Copy Windows installation files
echo "Copying Windows installation files (this may take a while)..."
cp -r "$ISO_MOUNT"/* "$MOUNT_POINT/"

# Create boot configuration
echo "Setting up boot configuration..."
if [ -d "$MOUNT_POINT/boot" ]; then
    mkdir -p "$MOUNT_POINT/boot/grub" 2>/dev/null
    cp "$ISO_MOUNT/boot/grub/memdisk" "$MOUNT_POINT/boot/grub/" 2>/dev/null
    cp "$ISO_MOUNT/boot/grub/win.iso" "$MOUNT_POINT/boot/grub/" 2>/dev/null
fi

# Sync and cleanup
echo "Finalizing installation..."
sync

# Unmount everything
umount "$ISO_MOUNT"
umount "$MOUNT_POINT"
rm -rf "$ISO_MOUNT" "$MOUNT_POINT"

# Create custom GRUB entry
GRUB_CUSTOM_FILE="/etc/grub.d/40_custom"

# Backup existing custom file if it exists
if [ -f "$GRUB_CUSTOM_FILE" ]; then
    cp "$GRUB_CUSTOM_FILE" "${GRUB_CUSTOM_FILE}.backup"
fi

echo "Creating GRUB entry..."
cat << EOF > "$GRUB_CUSTOM_FILE"
#!/bin/sh
exec tail -n +3 \$0
menuentry "Windows Installation (on $TARGET_PARTITION)" {
    insmod part_gpt
    insmod fat
    insmod search_fs_uuid
    insmod ntfs
    set root=(hd0,$PART_NUM)
    chainloader /bootmgr
    boot
}
EOF

# Make the custom file executable
chmod +x "$GRUB_CUSTOM_FILE"

# Generate GRUB configuration
echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "Setup complete! Here are some important notes:"
echo "1. Windows installation files have been copied to: $TARGET_PARTITION"
echo "2. When you reboot, select 'Windows Installation (on $TARGET_PARTITION)' from the GRUB menu"
echo "3. The Windows installation will start automatically"
echo "4. During installation:"
echo "   - The partition is already prepared"
echo "   - Follow the Windows installation prompts"
echo "   - When asked where to install, select the partition you chose ($TARGET_PARTITION)"
echo "   - Partition size: $(( $PART_SIZE / 1024 / 1024 / 1024 )) GB"
echo ""
echo "Current partition status:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p "$TARGET_PARTITION"
echo ""
echo "You can now reboot your system to start the Windows installation."
