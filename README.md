# Lnxboot - Universal Linux-Windows Dual Boot Setup Utility

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A robust command-line utility for setting up Windows dual-boot environments on Linux systems. Lnxboot automates the process of creating a bootable Windows installation environment from an ISO file, handling partitioning, and configuring the bootloader across various Linux distributions.

## Features

- **Universal Distribution Support**: Compatible with major Linux distributions and package managers
- **Automatic Package Management**: Supports apt, dnf, pacman, zypper, and rpm-ostree
- **UEFI and Legacy BIOS Support**: Handles both modern UEFI and legacy BIOS systems
- **Secure Boot Configuration**: Provides guidance for Secure Boot settings
- **Comprehensive Logging**: Detailed logging for troubleshooting
- **Data Safety**: Multiple confirmation steps and backup creation
- **Smart Drive Detection**: Supports both SATA and NVMe storage devices

## Prerequisites

- Root privileges (sudo access)
- A valid Windows ISO file
- Sufficient disk space for Windows installation
- One of the following package managers:
  - apt (Debian/Ubuntu)
  - dnf/yum (Fedora/RHEL)
  - pacman (Arch Linux)
  - zypper (openSUSE)
  - rpm-ostree (Fedora Silverblue/Kinoite)

## Required Packages

The script will automatically install these if missing:
- ntfs-3g
- grub2-tools or grub-common
- util-linux
- coreutils

## Installation

```bash
git clone https://github.com/yourusername/lnxboot.git
cd lnxboot
chmod +x Lnxboot.sh
```

## Usage

```bash
sudo ./Lnxboot.sh /path/to/windows.iso
```

### Example

```bash
sudo ./Lnxboot.sh ~/Downloads/Windows11.iso
```

## Supported Distributions

- Fedora (including Silverblue/Kinoite)
- Ubuntu/Debian
- Arch Linux
- openSUSE
- Red Hat Enterprise Linux
- Other distributions using supported package managers

## System Requirements

- **Minimum Disk Space**: 
  - 64GB for Windows 11
  - 32GB for Windows 10
- **Partition Type**: GPT for UEFI systems, MBR for Legacy BIOS
- **File Systems**: NTFS support required
- **Boot System**: GRUB2 bootloader

## Safety Measures

1. Automatic backup of GRUB configuration
2. Multiple user confirmations before destructive operations
3. Comprehensive error checking
4. Safe cleanup on script termination
5. Detailed logging for troubleshooting

## Troubleshooting

### Common Issues

1. **GRUB Not Updated**
   ```bash
   sudo grub2-mkconfig -o /boot/grub2/grub.cfg   # For RHEL-based systems
   sudo update-grub                              # For Debian-based systems
   ```

2. **Package Manager Errors**
   ```bash
   # Manual package installation
   # Debian/Ubuntu
   sudo apt install ntfs-3g grub-common
   
   # Fedora
   sudo dnf install ntfs-3g grub2-tools
   
   # Arch Linux
   sudo pacman -S ntfs-3g grub
   
   # openSUSE
   sudo zypper install ntfs-3g grub2
   
   # Fedora Silverblue/Kinoite
   sudo rpm-ostree install ntfs-3g grub2-tools
   ```

3. **Secure Boot Issues**
   - Disable Secure Boot in BIOS/UEFI settings
   - Enable CSM (Compatibility Support Module) if available

## Logging

- Log file location: `/var/log/lnxboot.log`
- Contains detailed information about:
  - Package installation attempts
  - Partition operations
  - GRUB configuration changes
  - Error messages

## Security Considerations

- Script requires root privileges
- Creates backups of critical system files
- Verifies file integrity before operations
- Sanitizes user inputs
- Handles sensitive operations safely

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This script modifies system boot configuration and partitions. While it includes safety measures, always backup important data before use. The authors are not responsible for data loss or system issues.

## Author

- Original Author: kleosr

## Version History

- 1.0.0: Initial release
- 1.1.0: Added universal distribution support
- 1.2.0: Enhanced UEFI support
- 1.3.0: Added comprehensive logging
