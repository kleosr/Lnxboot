# 🪟 Lnxboot - Windows ISO Installer for Linux

> Because who needs a USB stick anyway? 🤷‍♂️

Hey there! 👋 Tired of hunting for USB drives just to install Windows? This script's got your back! Install Windows directly from an ISO to any partition on your Linux machine. Perfect for dual-boot setups or when you just *need* Windows for that one specific thing (we've all been there).

## ✨ What's Cool About This?

- 🚫 No USB drive needed - save your USB for something else!
- 💪 Works with Windows 10 & 11
- 🔄 Supports both modern (UEFI) and legacy BIOS
- 🐧 Works on most Linux distros with GRUB
- 🎯 Super simple to use (seriously, it's just one command!)

## 📋 Before You Start

You'll need:
- A Linux system (duh! 😉)
- Root access (sudo privileges)
- GRUB bootloader
- A partition for Windows (30GB+ recommended)
- A Windows ISO file (grab it from Microsoft)

## 🛠️ Get These Packages First

```bash
# On Arch (btw) 😎
sudo pacman -S grub util-linux coreutils

# On Ubuntu/Debian
sudo apt-get install grub2 util-linux coreutils
```

## 🚀 Let's Do This!

1. Make it executable:
```bash
chmod +x lnxboot.sh
```

2. Run it (with sudo, because we're doing some serious stuff here):
```bash
sudo ./lnxboot.sh /path/to/your/windows.iso
```

3. Pick your partition when it shows you something like this:
```
🔍 Let's see what drives you've got...
----------------------------------------
NAME    SIZE  FSTYPE MOUNTPOINT LABEL
/dev/sda1  200M  vfat   /boot/efi
/dev/sda2  50G   ext4   /        
/dev/sda3  30G   vfat              <- Maybe this one? 😉
----------------------------------------
```

4. Follow the prompts (they're friendly, promise!)
5. Reboot when it's done
6. Pick "Windows" from your GRUB menu
7. Finish the Windows setup like usual

## ⚠️ Heads Up!

- **BACKUP YOUR STUFF!** Seriously, the script will format the partition you choose
- Need at least 30GB for Windows (more if you like installing games)
- Don't accidentally format your Linux partition (that would be a bad day 😅)
- If you've got Secure Boot enabled in BIOS, turn it off
- Make sure your Windows ISO is legit and not corrupted

## 🔧 Common Gotchas & Fixes

Having issues? Don't panic! Try these:

1. **"No space left"** error?
   - Check if you've got enough space (duh!)
   - Make sure the partition isn't mounted

2. **Can't see Windows in GRUB?**
   ```bash
   # Ubuntu/Debian folks:
   sudo update-grub

   # Arch gang:
   sudo grub-mkconfig -o /boot/grub/grub.cfg
   ```

3. **See some read-only warnings?**
   - That's normal! ISOs are always read-only
   - Your installation will work fine

## 🤝 Wanna Help?

Found a bug? Got an idea? Want to help? Awesome!

1. Open an issue - tell us what's up
2. Got improvements? Send a PR!
3. Share it with others who might need it

## 📜 License

MIT License - do whatever you want with it! Just don't blame us if something goes wrong 😉

## 👏 Credits

Made with ❤️ (and lots of ☕) by the community
Maintained by KleoSr

---
*P.S. If this script saved you from hunting for a USB drive, maybe give it a star? 🌟*
