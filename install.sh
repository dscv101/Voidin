#!/bin/bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###################
# Global Variables #
###################

DEVICE="/dev/nvme0n1"
USERNAME="dscv"
HOSTNAME="blazar"
TIMEZONE="Americas/Chicago"
KEYMAP="us"
LANG="en_US.UTF-8"

# Partition sizes (in MB)
BOOT_SIZE=2048      # 2GB for EFI/boot
SWAP_SIZE=40960     # 40GB for swap

# System configuration
ROOT_SIZE=153600    # 100GB
VAR_SIZE=153600      # 50GB

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

######################
# Utility Functions  #
######################

log() {
    echo -e "${GREEN}[+] ${1}${NC}"
}

warn() {
    echo -e "${YELLOW}[!] ${1}${NC}"
}

error() {
    echo -e "${RED}[-] ${1}${NC}"
    exit 1
}
install_pre() {
    xbps-install -Sy xbps
    xbps-install -Syu git github-cli nano u2f-hidraw-policy ykpers ykpers-gui dbus eudev elogind
    ln -s /etc/sv/{dbus,udevd,elogind} /var/service/
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        error "System not booted in UEFI mode"
    fi
}

check_yubikey() {
    if ! ykinfo -v >/dev/null 2>&1; then
        error "No Yubikey detected"
    fi
}

validate_inputs() {
    [[ -z "$DEVICE" ]] && error "No device specified"
    [[ -z "$USERNAME" ]] && error "No username specified"
    [[ ! -b "$DEVICE" ]] && error "Invalid device: $DEVICE"
}

######################
# Setup Functions    #
######################

install_prerequisites() {
    log "Installing prerequisites..."
    xbps-install -Syu || error "Failed to update system"
    xbps-install -y \
        ykpers \
        ykclient \
        ykclient-devel \
        ykneomgr \
        ykpers-gui \
        ykpivmgr \
        yubico-piv-tool \
        lvm2 \
        gptfdisk \
        cryptsetup \
        xfsprogs \
        systemd-boot \
        efibootmgr || error "Failed to install prerequisites"
}

setup_yubikey() {
    log "Setting up Yubikey..."
    
    # Check if slot 2 is already programmed
    if ! ykpersonalize -2 -ochal-resp -ochal-hmac -ohmac-lt64 -oserial-api-visible; then
        error "Failed to configure Yubikey slot 2"
    fi

    # Generate and store challenge
    local challenge
    challenge=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64) || error "Failed to generate challenge"
    mkdir -p /root/setup
    echo "$challenge" > /root/setup/luks-challenge || error "Failed to save challenge"
    chmod 600 /root/setup/luks-challenge

    # Test Yubikey response
    if ! ykchalresp -2 "$challenge" >/dev/null 2>&1; then
        error "Failed to test Yubikey response"
    fi
}

prepare_disk() {
    log "Preparing disk ${DEVICE}..."
    
    # Create partition table
    sgdisk -Z "$DEVICE" || error "Failed to zero disk"
    sgdisk -o "$DEVICE" || error "Failed to create GPT"

    # Calculate partition sizes
    local start_sector=2048
    local sector_size
    sector_size=$(blockdev --getss "$DEVICE")
    local boot_sectors=$((BOOT_SIZE * 1024 * 1024 / sector_size))
    local swap_sectors=$((SWAP_SIZE * 1024 * 1024 / sector_size))

    # Create partitions
    sgdisk -n "1:${start_sector}:+${boot_sectors}" -t "1:EF00" -c "1:boot" "$DEVICE" || error "Failed to create boot partition"
    sgdisk -n "2:$((start_sector + boot_sectors)):+${swap_sectors}" -t "2:8200" -c "2:swap" "$DEVICE" || error "Failed to create swap partition"
    sgdisk -n "3:$((start_sector + boot_sectors + swap_sectors)):-0" -t "3:8E00" -c "3:system" "$DEVICE" || error "Failed to create system partition"
}

setup_encryption() {
    log "Setting up encryption..."
    
    local system_partition="${DEVICE}p3"
    local key_file="/root/setup/luks-key"
    local challenge
    challenge=$(cat /root/setup/luks-challenge)
    local response
    response=$(ykchalresp -2 "$challenge") || error "Failed to get Yubikey response"

    # Generate key file
    dd if=/dev/urandom of="$key_file" bs=512 count=4 || error "Failed to generate key file"
    chmod 600 "$key_file"

    # Create composite key
    echo -n "$response" | cat - "$key_file" > /root/setup/composite-key || error "Failed to create composite key"

    # Format LUKS container
    cryptsetup luksFormat --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --iter-time 5000 \
        --sector-size 4096 \
        --label void_crypt \
        --key-file /root/setup/composite-key \
        "$system_partition" || error "Failed to create LUKS container"

    # Add backup password
    cryptsetup luksAddKey --key-file /root/setup/composite-key "$system_partition" || error "Failed to add backup password"

    # Open LUKS container
    cryptsetup luksOpen --key-file /root/setup/composite-key "$system_partition" void_crypt || error "Failed to open LUKS container"
}

setup_lvm() {
    log "Setting up LVM..."
    
    # Create physical volume
    pvcreate --dataalignment 1m /dev/mapper/void_crypt || error "Failed to create PV"

    # Create volume group
    vgcreate --physicalextentsize 4M void /dev/mapper/void_crypt || error "Failed to create VG"

    # Create logical volumes
    lvcreate -L "${ROOT_SIZE}M" -n root void || error "Failed to create root LV"
    lvcreate -L "${VAR_SIZE}M" -n var void || error "Failed to create var LV"
    lvcreate -l 100%FREE -n home void || error "Failed to create home LV"
}

format_filesystems() {
    log "Formatting filesystems..."
    
    # Format boot partition
    mkfs.vfat -F32 -n VOID_BOOT "${DEVICE}p1" || error "Failed to format boot partition"

    # Format swap
    mkswap -L void_swap "${DEVICE}p2" || error "Failed to format swap"

    # Format LVM volumes with XFS
    local xfs_options="-d su=128k,sw=1 -m crc=1,finobt=1 -i size=512"
    mkfs.xfs -f -L void_root $xfs_options /dev/void/root || error "Failed to format root"
    mkfs.xfs -f -L void_var $xfs_options /dev/void/var || error "Failed to format var"
    mkfs.xfs -f -L void_home $xfs_options /dev/void/home || error "Failed to format home"
}

mount_filesystems() {
    log "Mounting filesystems..."
    
    # Mount root
    mount -o noatime,nodiratime /dev/void/root /mnt || error "Failed to mount root"

    # Create mount points
    mkdir -p /mnt/{boot,var,home}

    # Mount other filesystems
    mount -o noatime,nodiratime,flush,iocharset=utf8 "${DEVICE}p1" /mnt/boot || error "Failed to mount boot"
    mount -o noatime,nodiratime /dev/void/var /mnt/var || error "Failed to mount var"
    mount -o noatime,nodiratime /dev/void/home /mnt/home || error "Failed to mount home"

    # Enable swap
    swapon "${DEVICE}p2" || warn "Failed to enable swap"
}

install_base_system() {
    log "Installing base system..."

    # Copy xbps keys
    mkdir -p /mnt/var/db/xbps/keys
    cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys
    
    xbps-install -Sy -R https://alpha.de.repo.voidlinux.org/current -r /mnt \
        base-system \
        cryptsetup \
        lvm2 \
        xfsprogs \
        systemd-boot \
        efibootmgr \
        linux-firmware-amd \
        linux-headers \
        void-repo-nonfree \
        ykpers \
        ykpers-gui \
        u2f-hidraw-policy \
        eudev \
        dbus \
        pcsc-ccid \
        pcsclite \
        ykpivmgr \
        yubico-piv-tool \
        yubikey-manager \
        ykclient \
        ykclient-devel \
        ykneomgr \
        pam_yubico \
        wayland \
        niri \
        elogind \
        seatd \
        wayland-protocols \
        libinput \
        wlroots \
        ghostty \
        ghostty-dbg \
        ghostty-terminfo \
        firefox \
        thunar \
        wl-clipboard \
        pam-u2f || error "Failed to install base system"
}

configure_system() {
    log "Configuring system..."
    
    # Copy Yubikey configuration
    mkdir -p /mnt/etc/luks
    cp /root/setup/luks-challenge /mnt/etc/luks/
    chmod 600 /mnt/etc/luks/luks-challenge

    # Create unlock script
    cat > /mnt/etc/luks/unlock-yubikey << 'EOF'
#!/bin/bash
challenge=$(cat /etc/luks/luks-challenge)
response=$(ykchalresp -2 "$challenge" 2>/dev/null)

if [ -z "$response" ]; then
    echo "No Yubikey detected, falling back to password..." >&2
    /sbin/cryptsetup luksOpen --type luks2 "$1" void_crypt
else
    dd if=/dev/urandom of=/tmp/luks-key bs=512 count=4 2>/dev/null
    echo -n "$response" | cat - /tmp/luks-key | \
        /sbin/cryptsetup luksOpen --type luks2 --key-file - "$1" void_crypt
    shred -u /tmp/luks-key
fi
EOF
    chmod 700 /mnt/etc/luks/unlock-yubikey

    # Configure system settings
    echo "$HOSTNAME" > /mnt/etc/hostname
    echo "LANG=$LANG" > /mnt/etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

    # Create fstab
    cat > /mnt/etc/fstab << EOF
# Root partition
LABEL=void_root / xfs defaults,noatime,nodiratime 0 0

# Boot partition
LABEL=VOID_BOOT /boot vfat noatime,nodiratime,flush,iocharset=utf8 0 2

# Var partition
LABEL=void_var /var xfs defaults,noatime,nodiratime 0 0

# Home partition
LABEL=void_home /home xfs defaults,noatime,nodiratime 0 0

# Swap partition
LABEL=void_swap none swap pri=1,discard 0 0
EOF
}

setup_bootloader() {
    log "Setting up bootloader..."
    
    # Install systemd-boot
    bootctl --path=/mnt/boot install || error "Failed to install systemd-boot"

    # Configure loader
    cat > /mnt/boot/loader/loader.conf << EOF
default void
timeout 4
console-mode max
editor no
EOF

    # Create void entry
    cat > /mnt/boot/loader/entries/void.conf << EOF
title   Void Linux
linux   /vmlinuz
initrd  /initramfs.img
options rd.luks.name=$(blkid -s UUID -o value "${DEVICE}p3")=void_crypt rd.luks.options=timeout=180 rd.lvm.vg=void root=/dev/void/root rw rootflags=noatime,nodiratime quiet loglevel=3 rd.auto=1 luks.unlock=/etc/luks/unlock-yubikey
EOF

    # Configure dracut
    cat > /mnt/etc/dracut.conf.d/10-crypt.conf << EOF
add_dracutmodules+=" crypt lvm "
add_drivers+=" nvme ykfde "
install_items+=" /etc/luks/unlock-yubikey /etc/luks/luks-challenge /usr/bin/ykchalresp "
compress="zstd"
hostonly="yes"
EOF

    # Create crypttab
    echo "void_crypt UUID=$(blkid -s UUID -o value "${DEVICE}p3") none luks,timeout=180,tries=3" > /mnt/etc/crypttab
}

configure_users() {
    log "Configuring users..."
    
    # Set root password
    chroot /mnt passwd root || error "Failed to set root password"

    # Create user
    chroot /mnt useradd -m -G wheel,audio,video,input "$USERNAME" || error "Failed to create user"
    chroot /mnt passwd "$USERNAME" || error "Failed to set user password"

    # Configure sudo
    echo "%wheel ALL=(ALL) ALL" > /mnt/etc/sudoers.d/wheel
    chmod 440 /mnt/etc/sudoers.d/wheel
}

cleanup() {
    log "Cleaning up..."
    
    # Remove sensitive files
    rm -rf /root/setup

    # Unmount filesystems
    umount -R /mnt || warn "Failed to unmount filesystems"
    
    # Close LUKS container
    cryptsetup close void_crypt || warn "Failed to close LUKS container"
}

#################
# Main Script   #
#################

main() {
    # Check requirements
    # install_pre
    check_root
    check_uefi
    check_yubikey

    # Get user input
    read -rp "Enter device path (e.g., /dev/nvme0n1): " DEVICE
    read -rp "Enter username: " USERNAME

    # Validate inputs
    # validate_inputs

    # Confirm installation
    warn "This will DESTROY ALL DATA on $DEVICE!"
    read -rp "Are you sure you want to continue? (y/N): " confirm
    [[ "${confirm,,}" != "y" ]] && exit 1

    # Run installation steps
    install_prerequisites
    setup_yubikey
    prepare_disk
    setup_encryption
    setup_lvm
    format_filesystems
    mount_filesystems
    install_base_system
    configure_system
    setup_bootloader
    configure_users
    cleanup

    log "Installation complete! You can now reboot."
}

# Run main function
main "$@"
