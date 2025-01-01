#!/usr/bin/env bash
# void_install.sh - Complete Void Linux Installation Script

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Script version
VERSION="1.0.0"

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define log file
LOG_FILE="/tmp/void_install.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration variables
HOSTNAME="void"
USERNAME=""
PASSWORD=""
TIMEZONE="UTC"
DISK=""
WIFI_SSID=""
WIFI_PASSWORD=""
KERNEL_VERSION="6.12.6"
EFI_SIZE="513"
ROOT_SIZE="200"
VAR_SIZE="10"
TMP_SIZE="5"
SWAP_SIZE="16"

# Source configuration modules
source "${SCRIPT_DIR}/modules/helpers.sh"
source "${SCRIPT_DIR}/modules/configs.sh"
source "${SCRIPT_DIR}/modules/kernel.sh"
source "${SCRIPT_DIR}/modules/development.sh"

print_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
 _    __      _     __   __    _                    
| |  / /___  (_)___/ /  / /   (_)___  __  ___  _____
| | / / __ \/ / __  /  / /   / / __ \/ / / / |/_/ _ \
| |/ / /_/ / / /_/ /  / /___/ / / / / /_/ />  </  __/
|___/\____/_/\__,_/  /_____/_/_/ /_/\__,_/_/|_|\___/ 
                                                      
EOF
    echo -e "Version: ${VERSION}${NC}"
    echo
}

check_requirements() {
    log "Checking installation requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
    
    # Check if running in UEFI mode
    if [[ ! -d /sys/firmware/efi ]]; then
        error "System must be booted in UEFI mode"
    fi
    
    # Check for required tools
    local required_tools=(
        parted
        mkfs.vfat
        cryptsetup
        lvm2
        wget
        git
        curl
    )
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "Required tool not found: $tool"
        fi
    done
}

collect_user_input() {
    log "Collecting user input..."
    
    # Hostname
    read -rp "Enter hostname [void]: " input_hostname
    HOSTNAME=${input_hostname:-void}
    
    # Username
    while [[ -z "$USERNAME" ]]; do
        read -rp "Enter username: " USERNAME
        if [[ "$USERNAME" =~ [^a-z0-9-] ]]; then
            echo "Username can only contain lowercase letters, numbers, and hyphens"
            USERNAME=""
        fi
    done
    
    # Password
    while true; do
        read -rsp "Enter password for $USERNAME: " PASSWORD
        echo
        read -rsp "Confirm password: " PASSWORD2
        echo
        [[ "$PASSWORD" == "$PASSWORD2" ]] && break
        echo "Passwords don't match. Try again."
    done
    
    # Timezone
    read -rp "Enter timezone [UTC]: " input_timezone
    TIMEZONE=${input_timezone:-UTC}
    if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
        error "Invalid timezone: $TIMEZONE"
    fi
    
    # Installation disk
    while true; do
        lsblk
        read -rp "Enter installation disk (e.g., /dev/nvme0n1): " DISK
        if [[ -b "$DISK" ]]; then
            if confirm "WARNING: All data on $DISK will be erased. Continue?"; then
                break
            fi
        else
            echo "Invalid disk device"
        fi
    done
    
    # WiFi setup
    if confirm "Do you need WiFi?"; then
        read -rp "Enter WiFi SSID: " WIFI_SSID
        read -rsp "Enter WiFi password: " WIFI_PASSWORD
        echo
    fi
    
    # Show summary and confirm
    echo
    echo "Installation Summary:"
    echo "===================="
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Timezone: $TIMEZONE"
    echo "Disk: $DISK"
    if [[ -n "$WIFI_SSID" ]]; then
        echo "WiFi: $WIFI_SSID"
    fi
    echo
    
    if ! confirm "Proceed with installation?"; then
        exit 0
    fi
}

setup_logging() {
    # Initialize log file
    echo "Void Linux Installation Log - $(date)" > "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
    
    # Redirect stdout and stderr to both console and log file
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

setup_network() {
    log "Setting up network connection..."
    
    if [[ -n "$WIFI_SSID" ]]; then
        wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" > /etc/wpa_supplicant/wpa_supplicant.conf
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf || error "Failed to start wpa_supplicant"
        dhcpcd wlan0 || error "Failed to start dhcpcd"
    fi
    
    # Wait for network
    local retries=0
    while ! ping -c 1 voidlinux.org >/dev/null 2>&1; do
        ((retries++))
        if ((retries > 10)); then
            error "Network connection failed"
        fi
        sleep 2
    done
    
    log "Network connection established"
}

main() {
    print_banner
    setup_logging
    check_requirements
    collect_user_input
    setup_network
    
    # Main installation steps
    prepare_disk
    mount_filesystems
    install_base_system
    configure_system
    install_bootloader
    configure_kernel
    setup_development_environment
    create_user
    configure_services
    finalize_installation
    
    log "Installation completed successfully!"
    log "You can now reboot your system."
}

# Run the script
main "$@"
