#!/usr/bin/env bash
# modules/kernel.sh - Kernel configuration and build

configure_kernel() {
    log "Configuring and building custom kernel..."
    
    # Enter kernel source directory
    cd /mnt/usr/src || error "Failed to enter source directory"
    
    # Download kernel source
    wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" || \
        error "Failed to download kernel source"
    
    tar xf "linux-${KERNEL_VERSION}.tar.xz" || error "Failed to extract kernel source"
    cd "linux-${KERNEL_VERSION}" || error "Failed to enter kernel directory"
    
    log "Downloading and applying patches..."
    
    # Download BORE scheduler patch
    wget https://raw.githubusercontent.com/firelzrd/bore-scheduler/main/bore-current.patch || \
        error "Failed to download BORE scheduler patch"
    
    patch -p1 < bore-current.patch || error "Failed to apply BORE scheduler patch"
    
    # Download and apply BBR3 patch
    wget https://raw.githubusercontent.com/google/bbr/v3/linux/net/ipv4/tcp_bbr3.c || \
        error "Failed to download BBR3 patch"
    
    cp tcp_bbr3.c net/ipv4/ || error "Failed to copy BBR3 source"
    
    log "Configuring kernel..."
    
    # Create base configuration
    make x86_64_defconfig || error "Failed to create base config"
    
    # Apply optimizations
    ./scripts/config \
        --set-val CONFIG_LOCALVERSION "-bore-bbr3" \
        \
        # CPU Optimizations
        -e X86_AMD_PLATFORM_DEVICE \
        -e PROCESSOR_SELECT \
        -e CPU_SUP_AMD \
        -e X86_MCE_AMD \
        -e PERF_EVENTS_AMD_POWER \
        -e AMD_MEM_ENCRYPT \
        -e NUMA \
        -e AMD_NUMA \
        -e NUMA_BALANCING \
        -e X86_ACPI_CPUFREQ \
        -e AMD_ACPI_POWER \
        -e AMD_PMC \
        \
        # BORE Scheduler
        -e SCHED_BORE \
        -d SCHED_ALT \
        -e FAIR_GROUP_SCHED \
        -e CFS_BANDWIDTH \
        -e SCHED_AUTOGROUP \
        -e SCHED_SMT \
        \
        # Network/BBR3
        -e TCP_CONG_BBR3 \
        -e DEFAULT_BBR3 \
        -e TCP_CONGESTION_CONTROL \
        -e NET_SCH_FQ \
        -e NET_SCH_FQ_CODEL \
        \
        # Performance
        -e PREEMPT \
        -e HZ_1000 \
        -e NO_HZ_FULL \
        -e RCU_NOCB_CPU \
        -e TRANSPARENT_HUGEPAGE \
        -e TRANSPARENT_HUGEPAGE_ALWAYS \
        \
        # Hardware Support
        -e NVME_CORE \
        -e BLK_DEV_NVME \
        -e NVME_MULTIPATH \
        -e NVME_HWMON \
        -e XFS_FS \
        -e CRYPTO_USER \
        -e CRYPTO_AES_NI_INTEL \
        -e CRYPTO_SHA256_SSSE3 \
        \
        # Security
        -e SECURITY \
        -e SECURITY_NETWORK \
        -e SECURITY_SELINUX \
        -e SECURITY_APPARMOR \
        -e DEFAULT_SECURITY_APPARMOR \
        || error "Failed to configure kernel"

    # Additional kernel parameters
    cat >> .config << EOF
CONFIG_HZ=1000
CONFIG_RCU_NOCB_CPU_ALL=y
CONFIG_NUMA_AWARE_SPINLOCKS=y
CONFIG_TMPFS_XATTR=y
CONFIG_ZSWAP=y
CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZ4=y
CONFIG_ZSWAP_ZPOOL_DEFAULT_ZSMALLOC=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_NR_CPUS=16
CONFIG_RQ_MC=y
CONFIG_RQ_ALLOC_CACHE_SIZE=8192
CONFIG_RWSEM_SPIN_ON_OWNER=y
EOF

    log "Building kernel..."
    
    # Determine number of CPU cores for parallel build
    local cpus=$(nproc)
    log "Using $cpus CPU cores for kernel build"
    
    # Build kernel and modules
    make -j"${cpus}" all || error "Kernel build failed"
    
    log "Installing kernel modules..."
    make modules_install || error "Failed to install kernel modules"
    
    log "Installing kernel..."
    make install || error "Failed to install kernel"
    
    # Update boot configuration
    log "Updating boot configuration..."
    
    # Generate new initramfs
    chroot /mnt xbps-reconfigure -f linux"${KERNEL_VERSION}" || \
        error "Failed to generate initramfs"
    
    # Update bootloader entry
    local kernel_version=$(make kernelrelease)
    cat > /mnt/boot/efi/loader/entries/void-custom.conf << EOF
title Void Linux (Custom Kernel ${kernel_version})
linux /vmlinuz-${kernel_version}
initrd /initramfs-${kernel_version}.img
options cryptdevice=UUID=$(blkid -s UUID -o value ${DISK}2):cryptroot:allow-discards \
    root=/dev/vg0/root rw \
    amd_pstate=active \
    processor.max_cstate=1 \
    rcu_nocbs=0-15 \
    nohz_full=1-15 \
    threadirqs \
    default_hugepagesz=2M \
    hugepages=3072 \
    iommu=pt \
    idle=nomwait \
    processor.energy_perf_bias=0 \
    amdgpu.ppfeaturemask=0xffffffff \
    pcie_aspm=off \
    pci=pcie_bus_perf \
    nvidia-drm.modeset=1 \
    nvidia.NVreg_UsePageAttributeTable=1
EOF

    # Set as default boot entry
    sed -i 's/^default.*/default void-custom/' /mnt/boot/efi/loader/loader.conf

    log "Kernel configuration and build completed"
}
