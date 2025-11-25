#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

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

is_package_installed() {
    local package="$1"
    local pkg_manager=$(detect_package_manager)
    
    case $pkg_manager in
        "apt")
            dpkg -l "$package" >/dev/null 2>&1
            ;;
        "dnf"|"yum"|"rpm-ostree")
            rpm -q "$package" >/dev/null 2>&1
            ;;
        "pacman")
            pacman -Q "$package" >/dev/null 2>&1
            ;;
        "zypper")
            rpm -q "$package" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Root privileges required for package installation"
        return 1
    fi
    return 0
}

install_packages() {
    local pkg_manager=$(detect_package_manager)
    
    if [ "$pkg_manager" = "unknown" ]; then
        log_error "Unsupported package manager. Please install required packages manually"
        return 1
    fi
    
    if ! check_root_privileges; then
        return 1
    fi
    
    log_info "Detected package manager: $pkg_manager"
    
    case $pkg_manager in
        "rpm-ostree")
            if ! rpm-ostree install "$REQUIRED_PACKAGES_NTFS" "$REQUIRED_PACKAGES_GRUB_DNF" "$REQUIRED_PACKAGES_EFIBOOTMGR" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to install packages with rpm-ostree"
                return 1
            fi
            log_info "Packages installed. Please reboot and run the script again."
            exit 0
            ;;
        "apt")
            if ! apt-get update 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to update package lists"
                return 1
            fi
            if ! apt-get install -y "$REQUIRED_PACKAGES_NTFS" $REQUIRED_PACKAGES_GRUB_APT "$REQUIRED_PACKAGES_EFIBOOTMGR" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to install packages with apt-get"
                return 1
            fi
            ;;
        "dnf"|"yum")
            if ! $pkg_manager install -y "$REQUIRED_PACKAGES_NTFS" $REQUIRED_PACKAGES_GRUB_DNF "$REQUIRED_PACKAGES_EFIBOOTMGR" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to install packages with $pkg_manager"
                return 1
            fi
            ;;
        "pacman")
            if ! pacman -Sy --noconfirm "$REQUIRED_PACKAGES_NTFS" "$REQUIRED_PACKAGES_GRUB_PACMAN" "$REQUIRED_PACKAGES_EFIBOOTMGR" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to install packages with pacman"
                return 1
            fi
            ;;
        "zypper")
            if ! zypper install -y "$REQUIRED_PACKAGES_NTFS" $REQUIRED_PACKAGES_GRUB_ZYPPER "$REQUIRED_PACKAGES_EFIBOOTMGR" 2>&1 | tee -a "$LOG_FILE"; then
                log_error "Failed to install packages with zypper"
                return 1
            fi
            ;;
    esac
    
    log_info "Package installation completed successfully"
    return 0
}

check_command_exists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

check_requirements() {
    local missing_tools=()
    
    if ! check_command_exists mkfs.ntfs && ! check_command_exists mkntfs; then
        missing_tools+=("ntfs-3g (mkfs.ntfs or mkntfs)")
    fi
    
    if ! check_command_exists grub2-mkconfig && ! check_command_exists grub-mkconfig && ! check_command_exists update-grub; then
        missing_tools+=("grub tools (grub2-mkconfig, grub-mkconfig, or update-grub)")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_info "Missing required tools: ${missing_tools[*]}"
        log_info "Attempting to install required packages..."
        
        if ! install_packages; then
            log_error "Failed to install required packages. Please install manually:"
            for tool in "${missing_tools[@]}"; do
                log_error "  - $tool"
            done
            return 1
        fi
        
        if ! check_command_exists mkfs.ntfs && ! check_command_exists mkntfs; then
            log_error "NTFS formatting tool still not available after installation"
            return 1
        fi
        
        if ! check_command_exists grub2-mkconfig && ! check_command_exists grub-mkconfig && ! check_command_exists update-grub; then
            log_error "GRUB tools still not available after installation"
            return 1
        fi
    fi
    
    log_info "All required tools are available"
    return 0
}
