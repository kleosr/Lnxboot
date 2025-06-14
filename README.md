# Lnxboot - Windows Dual Boot Made Simple

A straightforward script that sets up Windows dual-boot on Linux systems. Just point it at a Windows ISO and it handles the rest.

## What it does

- Copies Windows installation files to a partition you choose
- Sets up GRUB to boot Windows alongside Linux
- Works with both UEFI and Legacy BIOS systems
- Supports most Linux distributions automatically

## Quick start

```bash
sudo ./Lnxboot.sh /path/to/windows.iso
```

That's it. The script will:
1. Show you available partitions
2. Ask which one to use for Windows
3. Format it and copy the Windows files
4. Add Windows to your boot menu

## Requirements

- Root access (sudo)
- A Windows ISO file
- At least 20GB free space on target partition
- One of these package managers: apt, dnf, yum, pacman, zypper, or rpm-ostree

The script installs any missing packages automatically.

## Supported systems

Works on most Linux distributions including:
- Ubuntu/Debian
- Fedora/RHEL
- Arch Linux
- openSUSE
- Fedora Silverblue/Kinoite

## Important notes

- **Backup your data first** - the target partition gets wiped
- **Disable Secure Boot** in your BIOS/UEFI before installing Windows
- After Windows installs, you might need to restore GRUB (the script tells you how)

## If something goes wrong

Check `/var/log/lnxboot.log` for details. Most issues are:

1. **Windows won't boot**: Try `sudo grub2-mkconfig -o /boot/grub2/grub.cfg`
2. **Missing packages**: The script usually handles this, but you can install manually
3. **UEFI issues**: Make sure Secure Boot is disabled

## License

MIT License - use it however you want.

## Contributing

Found a bug or want to improve something? Pull requests welcome.
