#!/usr/bin/env bash
# modules/helpers.sh - Helper functions for installation

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE"
    exit 1
}

warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

confirm() {
    read -rp "$1 (y/n) " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

prepare_disk() {
    log "Preparing disk $DISK..."
    
    # Unmount any existing partitions
    umount "${DISK}"* 2>/dev/null || true
    
    # Close any existing LUKS containers
    cryptsetup close cryptroot 2>/dev/null || true
    
    # Create partitions
    parted --script "${DISK}" \
        mklabel gpt \
        mkpart ESP fat32 1MiB "${EFI_SIZE}MiB" \
        set 1 boot on \
        mkpart primary "${EFI_SIZE}MiB" 100%
    
    log "Creating LUKS encryption..."
    cryptsetup luksFormat --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --iter-time 5000 \
        --pbkdf argon2id \
        --verify-passphrase \
        "${DISK}2"
    
    cryptsetup open "${DISK}2" cryptroot
    
    log "Setting up LVM..."
    pvcreate /dev/mapper/cryptroot
    vgcreate vg0 /dev/mapper/cryptroot
    
    # Create logical volumes
    lvcreate -L "${SWAP_SIZE}G" vg0 -n swap
    lvcreate -L "${ROOT_SIZE}G" vg0 -n root
    lvcreate -L "${VAR_SIZE}G" vg0 -n var
    lvcreate -L "${TMP_SIZE}G" vg0 -n tmp
    lvcreate -l 100%FREE vg0 -n home
    
    log "Formatting partitions..."
    # Format EFI partition
    mkfs.vfat -F32 "${DISK}1"
    
    # Format XFS partitions with optimizations
    local xfs_options="-d su=128k,sw=4 -m reflink=1,bigtime=1,crc=1,finobt=1,inode64=1 -l size=128m,version=2,sunit=32,su=128k -i size=512"
    for vol in root home var tmp; do
        mkfs.xfs ${xfs_options} "/dev/vg0/${vol}"
    done
    
    # Setup swap
    mkswap /dev/vg0/swap
    swapon /dev/vg0/swap
}

mount_filesystems() {
    log "Mounting filesystems..."
    
    # Mount root filesystem
    mount /dev/vg0/root /mnt
    
    # Create mount points
    mkdir -p /mnt/{home,var,tmp,boot/efi}
    
    # Mount other filesystems
    mount /dev/vg0/home /mnt/home
    mount /dev/vg0/var /mnt/var
    mount /dev/vg0/tmp /mnt/tmp
    mount "${DISK}1" /mnt/boot/efi
    
    # Verify mounts
    if ! mountpoint -q /mnt/boot/efi; then
        error "Failed to mount EFI partition"
    fi
}

install_base_system() {
    log "Installing base system..."
    
    # Install base packages
    XBPS_ARCH=x86_64 xbps-install -Sy -R https://alpha.de.repo.voidlinux.org/current -r /mnt \
        base-system \
        cryptsetup \
        lvm2 \
        ykfde \
        systemd \
        systemd-boot \
        NetworkManager \
        vim \
        sudo \
        apparmor \
        linux-headers \
        git \
        curl \
        wget \
        zsh \
        make \
        gcc \
        pkg-config \
        python3 \
        || error "Failed to install base packages"
    
    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab || error "Failed to generate fstab"
}

configure_system() {
    log "Configuring base system..."
    
    # Basic system configuration
    chroot /mnt /bin/bash -c "
        ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
        hwclock --systohc
        echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
        locale-gen
        echo 'LANG=en_US.UTF-8' > /etc/locale.conf
        echo '${HOSTNAME}' > /etc/hostname
        
        # Set root password
        echo 'root:${PASSWORD}' | chpasswd
        
        # Configure sudo
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
        chmod 440 /etc/sudoers.d/wheel
    " || error "Failed to configure base system"
}

create_user() {
    log "Creating user account..."
    
    chroot /mnt /bin/bash -c "
        useradd -m -G wheel,audio,video,input -s /bin/zsh '${USERNAME}'
        echo '${USERNAME}:${PASSWORD}' | chpasswd
        
        # Create user directories
        mkdir -p /home/${USERNAME}/{Documents,Downloads,Projects}
        chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
    " || error "Failed to create user account"
}

configure_services() {
    log "Configuring system services..."
    
    chroot /mnt /bin/bash -c "
        systemctl enable NetworkManager
        systemctl enable postgresql
        systemctl enable nvidia-performance
        systemctl enable cpu-power
        systemctl enable system-monitor
        systemctl enable apparmor
        systemctl enable system-maintenance.timer
    " || error "Failed to configure services"
}

finalize_installation() {
    log "Finalizing installation..."
    
    # Update initramfs
    chroot /mnt xbps-reconfigure -f linux"$(uname -r)"
    
    # Create backup of important configurations
    tar czf /mnt/root/system-config-backup.tar.gz \
        /mnt/etc/sysctl.d/ \
        /mnt/etc/systemd/system/ \
        /mnt/etc/X11/xorg.conf.d/ \
        /mnt/etc/default/ \
        /mnt/etc/modprobe.d/ \
        /mnt/etc/security/limits.d/ \
        /mnt/etc/zsh || warning "Failed to create configuration backup"
    
    # Clean package cache
    chroot /mnt vkpurge rm all
    
    # Final sync
    sync
}
