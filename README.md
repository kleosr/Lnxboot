![image_fx_ (5) (1)](https://github.com/user-attachments/assets/c3f8dd1a-62cf-4e5f-8a6c-abdfd817eba5)
# Windows ISO Boot Script | Linux No USB

A powerful Linux script that enables direct Windows installation from an ISO file to any hard drive partition without requiring a USB drive. Perfect for Linux users wanting to set up a dual-boot system with Windows.

## Features

- Direct ISO installation without USB media
- Compatible with Windows 10 and 11
- Works with both UEFI and Legacy BIOS systems
- Supports most GRUB-based Linux distributions
- Simple interactive interface

## Prerequisites

- Linux operating system
- Superuser (sudo) privileges
- GRUB bootloader installed
- Dedicated partition for Windows (minimum 30GB recommended)
- Windows ISO file

## Required Packages

```bash
# For Arch Linux
sudo pacman -S grub util-linux coreutils

# For Ubuntu/Debian
sudo apt-get install grub2 util-linux coreutils
```

## Usage

1. Make the script executable:
```bash
chmod +x lnxboot.sh
```

2. Run the script with sudo:
```bash
sudo ./lnxboot.sh /path/to/your/windows.iso
```

3. The script will display all available partitions:
```
Available partitions:
----------------------------------------
NAME    SIZE  FSTYPE MOUNTPOINT LABEL
/dev/sda1  200M  vfat   /boot/efi
/dev/sda2  50G   ext4   /
/dev/sda3  30G   vfat   
----------------------------------------
```

4. Select your target partition for Windows installation (e.g., /dev/sda3)
5. Confirm your selection when prompted
6. Wait for the installation process to complete
7. Reboot your computer and select "Windows Installation" from the GRUB menu

## Important Notes

 **WARNING:**
- The script will format the selected partition. Backup any important data beforehand
- The target partition must have sufficient space for Windows (minimum 30GB recommended)
- Do not select the partition containing your current Linux system
- Disable Secure Boot in BIOS if enabled
- Ensure your Windows ISO is valid and not corrupted

## Troubleshooting

1. "No space left on device" error:
   - Verify sufficient partition space
   - Ensure the partition is not mounted during installation

2. Windows not appearing in GRUB menu:
   - For Ubuntu/Debian: Run `sudo update-grub`
   - For Arch Linux: Run `sudo grub-mkconfig -o /boot/grub/grub.cfg`

3. "Warning: source write-protected, mounted read-only":
   - This is normal behavior (ISO is always mounted read-only)
   - Does not affect the installation process

## Contributing

We welcome contributions! Here's how you can help:
1. Open an issue for bugs or suggestions
2. Propose improvements
3. Submit pull requests

## License

This project is licensed under the MIT License

## Credits

Created by the community, for the community.  
Maintained by KleoSr
