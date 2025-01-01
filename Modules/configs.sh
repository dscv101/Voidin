#!/usr/bin/env bash
# modules/configs.sh - System configuration templates

create_nvidia_config() {
    log "Creating NVIDIA configuration..."
    
    mkdir -p /mnt/etc/X11/xorg.conf.d
    cat > /mnt/etc/X11/xorg.conf.d/10-nvidia.conf << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
    BoardName "GeForce GTX 970"
    Option "NoLogo" "true"
    Option "RegistryDwords" "EnableBrightnessControl=1"
    Option "TripleBuffer" "true"
    Option "AllowIndirectGLXProtocol" "off"
    Option "ForceFullCompositionPipeline" "on"
    Option "AllowExternalGpus" "false"
    Option "UseNvKmsCompositionPipeline" "true"
    Option "RenderAccel" "true"
    Option "AccelMethod" "glamor"
EndSection
EOF

    # Create NVIDIA performance service
    cat > /mnt/etc/systemd/system/nvidia-performance.service << 'EOF'
[Unit]
Description=NVIDIA Performance Mode
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi --persistence-mode=1
ExecStart=/usr/bin/nvidia-smi --power-limit=250
ExecStart=/usr/bin/nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1"
ExecStart=/usr/bin/nvidia-settings -a "[gpu:0]/GPUFanControlState=1"
ExecStart=/usr/bin/nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=60"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

create_system_optimizations() {
    log "Creating system optimization configurations..."
    
    # CPU Power Management
    cat > /mnt/etc/systemd/system/cpu-power.service << 'EOF'
[Unit]
Description=CPU Power Management
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ryzenadj --stapm-limit=142000 --fast-limit=142000 --slow-limit=142000 --tctl-temp=90
ExecStart=/usr/bin/cpupower frequency-set -g performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # System monitoring service
    cat > /mnt/etc/systemd/system/system-monitor.service << 'EOF'
[Unit]
Description=System Performance Monitoring
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do \
    date >> /var/log/system-stats.log; \
    echo "CPU:" >> /var/log/system-stats.log; \
    sensors | grep "Tctl" >> /var/log/system-stats.log; \
    echo "GPU:" >> /var/log/system-stats.log; \
    nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw --format=csv >> /var/log/system-stats.log; \
    echo "---" >> /var/log/system-stats.log; \
    sleep 60; \
done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Sysctl optimizations
    cat > /mnt/etc/sysctl.d/99-system-optimizations.conf << 'EOF'
# VM settings
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.max_map_count = 2147483642

# Network settings
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216
net.ipv4.tcp_congestion_control = bbr3
net.core.default_qdisc = fq

# File system
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Performance
kernel.sched_autogroup_enabled = 0
kernel.sched_migration_cost_ns = 5000000
EOF

    # System limits
    cat > /mnt/etc/security/limits.d/99-performance.conf << 'EOF'
* soft     nofile          1048576
* hard     nofile          1048576
* soft     nproc           unlimited
* hard     nproc           unlimited
* soft     memlock         unlimited
* hard     memlock         unlimited
EOF

    # I/O scheduler
    cat > /mnt/etc/udev/rules.d/60-scheduler.rules << 'EOF'
# Set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/read_ahead_kb}="2048"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/nr_requests}="2048"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rq_affinity}="2"
EOF
}

create_zsh_config() {
    log "Creating ZSH configuration..."
    
    mkdir -p /mnt/etc/zsh
    cat > /mnt/etc/zsh/zshrc << 'EOF'
# Performance Optimization
DISABLE_AUTO_UPDATE="true"
DISABLE_UPDATE_PROMPT="true"
skip_global_compinit=1
COMPLETION_WAITING_DOTS="true"

# History Configuration
HISTFILE=$HOME/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY

# Directory Navigation
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_MINUS

# Development Aliases
alias ls='exa --icons --git'
alias ll='exa -l --icons --git'
alias la='exa -la --icons --git'
alias cat='bat'
alias diff='delta'
alias grep='rg'
alias find='fd'
alias cd='z'

# Initialize starship prompt
eval "$(starship init zsh)"

# Initialize zoxide
eval "$(zoxide init zsh)"

# Direnv Configuration
eval "$(direnv hook zsh)"
EOF

    # Create Starship configuration
    mkdir -p /mnt/etc/skel/.config
    cat > /mnt/etc/skel/.config/starship.toml << 'EOF'
format = """
[╭─](bold green)$username$hostname$directory$git_branch$git_status$python$rust$golang$nodejs
[╰─](bold green)$character"""

[username]
style_user = "green bold"
style_root = "red bold"
format = "[$user]($style)"
disabled = false
show_always = true

[hostname]
ssh_only = false
format = "@[$hostname](bold blue) "
disabled = false

[directory]
truncation_length = 8
truncation_symbol = "…/"
home_symbol = "~"
read_only_style = "197"
read_only = "  "
format = "in [$path]($style)[$read_only]($read_only_style) "

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
vicmd_symbol = "[❮](bold green)"
EOF
}

create_maintenance_scripts() {
    log "Creating system maintenance scripts..."
    
    cat > /mnt/usr/local/bin/system-maintenance << 'EOF'
#!/bin/bash
# Update system
xbps-install -Su

# Update kernel if needed
xbps-reconfigure -f linux$(uname -r)

# Clear package cache
vkpurge rm all

# Clear journal
journalctl --vacuum-time=7d

# Database maintenance
if systemctl is-active postgresql >/dev/null 2>&1; then
    su - postgres -c "vacuumdb --all --analyze"
fi

# Update development tools
if command -v rustup >/dev/null 2>&1; then
    rustup update
fi

if command -v pip >/dev/null 2>&1; then
    pip list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 pip install -U
fi
EOF
    chmod +x /mnt/usr/local/bin/system-maintenance

    # Create maintenance timer
    cat > /mnt/etc/systemd/system/system-maintenance.timer << 'EOF'
[Unit]
Description=Weekly System Maintenance

[Timer]
OnCalendar=weekly
RandomizedDelaySec=1hour
Persistent=true

[Install]
WantedBy=timers.target
EOF
}
