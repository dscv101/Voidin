#!/bin/bash

# Exit on error
set -e
set -o pipefail

# Configuration variables
DISK="/dev/nvme0n1"  # NVMe drive
HOSTNAME="blazar"
USERNAME="dscv"
TIMEZONE="America/Chicago"  # Change this to your timezone
KEYMAP="us"
LANG="en_US.UTF-8"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 
   exit 1
fi

# Check if system is booted in UEFI mode
if [ ! -d "/sys/firmware/efi" ]; then
    echo "System not booted in UEFI mode!"
    exit 1
fi

# Check if target disk exists
if [ ! -b "${DISK}" ]; then
    echo "Target disk ${DISK} does not exist!"
    exit 1
fi

# Warn user about disk destruction
echo "WARNING: This will destroy all data on ${DISK}"
read -p "Are you sure you want to continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Clean up any existing LVM setup on target disk
if vgs vg0 &>/dev/null; then
    vgremove -f vg0
fi
if pvs "${DISK}p2" &>/dev/null; then
    pvremove -f "${DISK}p2"
fi

# Create partitions
echo "Creating partitions..."
sgdisk --zap-all "${DISK}"
parted -s "${DISK}" mklabel gpt
parted -s "${DISK}" mkpart ESP fat32 1MiB 2049MiB
parted -s "${DISK}" set 1 boot on
parted -s "${DISK}" mkpart primary 2049MiB 100%
sync

# Wait for kernel to register new partitions
sleep 2

# Format EFI partition
echo "Formatting EFI partition..."
mkfs.vfat -F32 "${DISK}p1"

# Setup LVM
echo "Setting up LVM..."
pvcreate "${DISK}p2"
vgcreate vg0 "${DISK}p2"
lvcreate -L 4G vg0 -n swap
lvcreate -l 100%FREE vg0 -n root

# Format partitions
echo "Formatting partitions..."
mkfs.xfs -f /dev/vg0/root
mkswap /dev/vg0/swap

# Mount partitions
echo "Mounting partitions..."
mount /dev/vg0/root /mnt
mkdir -p /mnt/boot
mount "${DISK}p1" /mnt/boot
swapon /dev/vg0/swap

# Install base system
echo "Installing base system..."
mkdir -p /mnt/var/db/xbps/keys
cp -a /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

XBPS_ARCH=x86_64-musl xbps-install -Sy -R https://alpha.de.repo.voidlinux.org/current/musl -r /mnt \
    base-system \
    lvm2 \
    void-repo-nonfree \
    linux-firmware-amd \
    nvidia470 \
    nvidia470-libs-32bit \
    nvidia470-libs \
    linux \
    linux-headers \
    gptfdisk \
    git \
    vim \
    elogind \
    dbus \
    wayland \
    wayland-protocols \
    mesa-dri \
    mesa-vulkan-nvidia470 \
    vulkan-loader \
    libspa-bluetooth \
    pipewire \
    pipewire-alsa \
    pipewire-jack \
    pipewire-pulse \
    wireplumber \
    xdg-desktop-portal \
    xdg-desktop-portal-wlr \
    xdg-user-dirs \
    xdg-utils \
    ghostty \
    ghostty-terminfo \
    grim \
    slurp \
    wl-clipboard \
    tlp \
    polkit \
    NetworkManager \
    chrony \
    socklog-void \
    libvirt \
    qemu \
    sudo \
    systemd-boot

# Generate fstab
mkdir -p /mnt/etc
genfstab -U -p /mnt > /mnt/etc/fstab

# Configure the new system
echo "Configuring new system..."
mkdir -p /mnt/etc/xbps.d
cp /etc/xbps.d/*-repository-*.conf /mnt/etc/xbps.d/

# Set up chroot environment
mount -t proc none /mnt/proc
mount -t sysfs none /mnt/sys
mount -o bind /dev /mnt/dev
mount -o bind /run /mnt/run

# Create chroot setup script
cat > /mnt/setup.sh << 'ENDOFSCRIPT'
#!/bin/bash
set -e
set -o pipefail

# Set hostname
echo "${HOSTNAME}" > /etc/hostname

# Set timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

# Set locale
echo "LANG=${LANG}" > /etc/locale.conf
echo "${LANG} UTF-8" >> /etc/default/libc-locales
xbps-reconfigure -f glibc-locales

# Set keymap
echo "KEYMAP=${KEYMAP}" > /etc/rc.conf

# Configure Wayland environment
mkdir -p /etc/environment.d
cat > /etc/environment.d/wayland.conf << 'EOF'
# Wayland environment variables
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=Wayland
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland-egl
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
GDK_BACKEND=wayland
CLUTTER_BACKEND=wayland
SDL_VIDEODRIVER=wayland
ELM_DISPLAY=wl
ECORE_EVAS_ENGINE=wayland
_JAVA_AWT_WM_NONREPARENTING=1
NO_AT_BRIDGE=1
NIXOS_OZONE_WL=1

# NVIDIA specific settings
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
LIBVA_DRIVER_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
WLR_DRM_NO_ATOMIC=1
EOF

# Configure XDG user directories
cat > /etc/xdg/user-dirs.defaults << 'EOF'
DESKTOP=Desktop
DOWNLOAD=Downloads
TEMPLATES=Templates
PUBLICSHARE=Public
DOCUMENTS=Documents
MUSIC=Music
PICTURES=Pictures
VIDEOS=Videos
EOF

# Configure bootloader
mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf << 'EOF'
default void-linux
timeout 3
console-mode max
editor no
EOF

cat > /boot/loader/entries/void-linux.conf << 'EOF'
title   Void Linux
linux   /vmlinuz
initrd  /initramfs.img
options root=/dev/vg0/root rw quiet loglevel=0 nvidia-drm.modeset=1
EOF

cat > /boot/loader/entries/void-linux-fallback.conf << 'EOF'
title   Void Linux (fallback)
linux   /vmlinuz
initrd  /initramfs.img
options root=/dev/vg0/root rw nvidia-drm.modeset=1
EOF

# Configure dracut for LVM
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/lvm.conf << 'EOF'
add_dracutmodules+=" lvm "
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
EOF

cat > /etc/dracut.conf.d/cmdline.conf << 'EOF'
kernel_cmdline="root=/dev/vg0/root rw quiet loglevel=0 nvidia-drm.modeset=1"
EOF

# Install bootloader
bootctl --path=/boot install
bootctl --path=/boot set-default void-linux
bootctl --path=/boot random-seed

# Configure kernel hooks for bootloader updates
mkdir -p /etc/kernel.d/post-install /etc/kernel.d/post-remove

cat > /etc/kernel.d/post-install/20-bootloader << 'EOF'
#!/bin/sh
exec bootctl --path=/boot update
EOF
chmod +x /etc/kernel.d/post-install/20-bootloader

cat > /etc/kernel.d/post-remove/20-bootloader << 'EOF'
#!/bin/sh
exec bootctl --path=/boot update
EOF
chmod +x /etc/kernel.d/post-remove/20-bootloader

# Configure NVIDIA settings
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

# Configure PipeWire
mkdir -p /etc/pipewire/pipewire.conf.d
ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/

# Generate XDG user directories for skeleton
mkdir -p /etc/skel/{Desktop,Downloads,Templates,Public,Documents,Music,Pictures,Videos}

# Set root password
echo "Set root password:"
passwd

# Create user account
useradd -m -G wheel,input,audio,video,network "${USERNAME}"
echo "Set user password for ${USERNAME}:"
passwd "${USERNAME}"

# Configure sudo
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# Enable services
ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
ln -s /etc/sv/polkitd /etc/runit/runsvdir/default/
ln -s /etc/sv/elogind /etc/runit/runsvdir/default/
ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/
ln -s /etc/sv/chronyd /etc/runit/runsvdir/default/
ln -s /etc/sv/socklog-unix /etc/runit/runsvdir/default/
ln -s /etc/sv/nanoklogd /etc/runit/runsvdir/default/

# Generate initramfs
xbps-reconfigure -fa
ENDOFSCRIPT

# Make setup script executable
chmod +x /mnt/setup.sh

# Chroot and run setup
chroot /mnt /setup.sh

# Clean up
echo "Cleaning up..."
rm -f /mnt/setup.sh
umount -R /mnt

echo "Installation complete! You can now reboot into your new system."
echo "Remember to remove the installation media before rebooting."