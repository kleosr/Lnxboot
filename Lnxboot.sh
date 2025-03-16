#!/bin/bash

# ╔═══════════════════════════════════════════╗
# ║         Linux Windows Boot Setup          ║
# ║    Because dual-booting should be easy    ║
# ║                                          ║
# ║  Created by: A sleep-deprived developer  ║
# ║  Last updated: When coffee was hot       ║
# ╚═══════════════════════════════════════════╝

# Fail fast if something goes wrong
set -e

# Trust me, you'll need this as root
if [ "$EUID" -ne 0 ]; then 
    echo "🛑 Hey! You need to run this with sudo!"
    echo "Try: sudo $0 /path/to/your/windows.iso"
    exit 1
fi

# No ISO? No party!
if [ -z "$1" ]; then
    echo "🤔 Hmm... Where's the Windows ISO?"
    echo "Usage: $0 /path/to/windows.iso"
    echo "Pro tip: Make sure it's a legit Windows ISO"
    exit 1
fi

ISO_PATH="$1"
MOUNT_POINT="/mnt/windows_iso_temp"
ISO_MOUNT="/mnt/iso_temp"

# Show what we're working with
echo "🔍 Let's see what drives you've got..."
echo "----------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p | grep "sd[a-z][0-9]" || echo "No drives found? That's weird... 🤔"
echo "----------------------------------------"

# Let's pick a victim... err, I mean, partition
echo "⌨️  Which partition should we use for Windows? (e.g., /dev/sda3)"
echo "WARNING: Choose wisely! This will DESTROY everything on that partition!"
read -p "Type partition path here: " TARGET_PARTITION

# Make sure we're not crazy
if ! lsblk "$TARGET_PARTITION" >/dev/null 2>&1; then
    echo "❌ Oops! Can't find $TARGET_PARTITION"
    echo "Did you type it correctly? No typos? 🤔"
    exit 1
fi

# Get the details (because math is hard)
PART_SIZE=$(lsblk -b -n -o SIZE "$TARGET_PARTITION" | head -n1)
PART_NAME=$(basename "$TARGET_PARTITION")
DISK_NAME=$(echo "$PART_NAME" | sed 's/[0-9]//g')
PART_NUM=$(echo "$PART_NAME" | sed 's/[^0-9]//g')

echo "🎯 Here's what you picked:"
echo "----------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p "$TARGET_PARTITION"
echo "----------------------------------------"

# Last chance to back out...
echo "⚠️  POINT OF NO RETURN ⚠️"
read -p "Sure about this? Your data will be GONE! (type 'y' to continue): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "😅 Phew! Crisis averted. Come back when you're ready!"
    exit 1
fi

# Check if ISO exists (and is actually an ISO)
if [ ! -f "$ISO_PATH" ]; then
    echo "❌ Can't find the ISO at: $ISO_PATH"
    echo "Did you download it? Is the path correct?"
    exit 1
fi

# Time to do the actual work
echo "🚀 Alright, let's do this! (Might take a while, grab a coffee)"

# Create mount points (and clean up any leftovers)
echo "📁 Making some temporary folders..."
rm -rf "$MOUNT_POINT" "$ISO_MOUNT" 2>/dev/null || true
mkdir -p "$MOUNT_POINT" "$ISO_MOUNT"

# Mount the ISO (pray it works)
echo "💿 Mounting the Windows ISO..."
mount -o loop "$ISO_PATH" "$ISO_MOUNT" || {
    echo "❌ Failed to mount ISO! Is it corrupted?"
    exit 1
}

# Mount target partition
echo "💽 Mounting your partition..."
umount "$TARGET_PARTITION" 2>/dev/null || true
mount "$TARGET_PARTITION" "$MOUNT_POINT" || {
    echo "❌ Failed to mount partition! Is it formatted?"
    umount "$ISO_MOUNT" 2>/dev/null
    exit 1
}

# Copy Windows files (this is where people usually go make coffee)
echo "📝 Copying Windows files... (perfect time for ☕)"
echo "This might take a while... Like, a WHILE while..."
cp -r "$ISO_MOUNT"/* "$MOUNT_POINT/" || {
    echo "❌ Copy failed! Check disk space maybe?"
    umount "$ISO_MOUNT" 2>/dev/null
    umount "$MOUNT_POINT" 2>/dev/null
    exit 1
}

# Boot config (fingers crossed)
echo "⚙️ Setting up boot stuff..."
if [ -d "$MOUNT_POINT/boot" ]; then
    mkdir -p "$MOUNT_POINT/boot/grub" 2>/dev/null
    cp "$ISO_MOUNT/boot/grub/memdisk" "$MOUNT_POINT/boot/grub/" 2>/dev/null
    cp "$ISO_MOUNT/boot/grub/win.iso" "$MOUNT_POINT/boot/grub/" 2>/dev/null
fi

# The cleanup crew
echo "🧹 Cleaning up..."
sync
umount "$ISO_MOUNT" || echo "Warning: Couldn't unmount ISO, but it's probably fine..."
umount "$MOUNT_POINT" || echo "Warning: Couldn't unmount partition, but it's probably fine..."
rm -rf "$ISO_MOUNT" "$MOUNT_POINT"

# GRUB magic
GRUB_CUSTOM_FILE="/etc/grub.d/40_custom"

# Backup because we're not savages
[ -f "$GRUB_CUSTOM_FILE" ] && cp "$GRUB_CUSTOM_FILE" "${GRUB_CUSTOM_FILE}.backup"

echo "🔧 Adding GRUB menu entry..."
cat << EOF > "$GRUB_CUSTOM_FILE"
#!/bin/sh
exec tail -n +3 \$0
# Added by Lnxboot.sh - Your friendly Windows installer
menuentry "Windows (on $TARGET_PARTITION) 🪟" {
    insmod part_gpt
    insmod fat
    insmod search_fs_uuid
    insmod ntfs
    set root=(hd0,$PART_NUM)
    chainloader /bootmgr
    boot
}
EOF

chmod +x "$GRUB_CUSTOM_FILE"

echo "🔄 Updating GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "
🎉 All done! Here's what you need to know:
----------------------------------------
1. Windows stuff is now on: $TARGET_PARTITION
2. Partition size: $(( $PART_SIZE / 1024 / 1024 / 1024 )) GB
3. When you reboot:
   - Pick 'Windows (on $TARGET_PARTITION) 🪟' from the boot menu
   - Follow the Windows installer (you know, Next, Next, Next...)
   - When it asks where to install, pick the partition you chose

Current partition status:
----------------------------------------"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p "$TARGET_PARTITION"
echo "
🔥 Pro Tips:
- If it doesn't boot, try running 'update-grub' again
- Make sure Secure Boot is disabled in BIOS
- If all else fails, there's always StackOverflow 😉

Now might be a good time to reboot! Good luck! 🚀"
