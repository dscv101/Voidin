# Optimized Void Linux Installation Script

A comprehensive installation script for Void Linux, optimized for development with AMD Ryzen 7 5800X, MSI X570, Seagate FireCuda NVMe, and NVIDIA GTX 970.

## Features

### System Configuration
- Custom kernel with BORE scheduler and BBR3
- Full disk encryption with LUKS2
- Optimized LVM on NVMe
- XFS filesystem with performance tuning
- NVIDIA driver optimization
- AMD CPU optimization
- Systemd-boot configuration
- Advanced power management

### Development Environment
- ZSH with modern configuration
- Direnv for environment management
- PostgreSQL with performance tuning
- Development tools for:
  - Python
  - Rust
  - Node.js
  - Go
- Neovim configuration
- Complete development toolchain

## Prerequisites

### Hardware Requirements
- CPU: AMD Ryzen 7 5800X
- Motherboard: MSI X570
- Storage: Seagate FireCuda 530 NVMe (1TB minimum recommended)
- GPU: NVIDIA GTX 970
- RAM: 32GB recommended
- USB drive (8GB minimum)
- Yubikey device
- Internet connection

### BIOS Settings
1. CPU Configuration:
   - AMD Cool'n'Quiet: Enabled
   - Global C-state Control: Disabled
   - PPC Adjustment: PState 0
   - AMD CPU fTPM: Enabled

2. Memory Configuration:
   - FCLK Frequency: 1800MHz
   - UCLK==MEMCLK: Enabled
   - XMP Profile: Enabled

3. PCIe Configuration:
   - PCIe Gen: Gen4
   - Above 4G Decoding: Enabled
   - Re-Size BAR Support: Enabled
   - PCIe ASPM: Disabled

4. Boot Configuration:
   - CSM: Disabled
   - Secure Boot: Enabled
   - Fast Boot: Enabled

## Installation

### Preparation
1. Download the script:
```bash
git clone https://github.com/yourusername/void-install.git
cd void-install
```

2. Make the script executable:
```bash
chmod +x install_void.sh
```

### Running the Installation
1. Boot from Void Linux live USB
2. Connect to the internet
3. Run the script:
```bash
./install_void.sh
```

### Installation Process
The script will:
1. Collect necessary information
2. Prepare storage devices
3. Install base system
4. Build custom kernel
5. Configure development environment
6. Set up security features
7. Optimize system performance

## Post-Installation

### Verification
After installation, verify:
1. System boot with LUKS encryption
2. Network connectivity
3. GPU driver functionality
4. Development environment setup
5. Database configuration
6. System performance

### First Boot Tasks
1. Update system:
```bash
sudo xbps-install -Su
```

2. Configure user environment:
```bash
# Initialize development directories
cd ~/Projects
# Set up version control
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Configuration Details

### Storage Layout
- 513MB EFI partition
- Encrypted LUKS2 container
- LVM with volumes:
  - 4GB swap
  - 30GB root
  - 10GB var
  - 5GB tmp
  - Remaining space for home

### Development Environment
- ZSH with:
  - Syntax highlighting
  - Auto-suggestions
  - Directory jumping
  - Git integration
  - Custom prompt

- Python Environment:
  - Virtual environments
  - Development tools
  - Testing framework
  - Code formatting

- Rust Environment:
  - Cargo configuration
  - Development tools
  - Performance optimization

- PostgreSQL:
  - Performance tuning
  - Development configuration
  - Automated maintenance

## Maintenance

### System Updates
```bash
# Regular system update
sudo system-maintenance

# Kernel update
sudo xbps-reconfigure -f linux$(uname -r)
```

### Backup
The script configures:
- System configuration backup
- Development environment backup
- Database backup
- User data backup

### Monitoring
- System performance monitoring
- Hardware temperature monitoring
- Resource usage tracking
- Database performance monitoring

## Troubleshooting

### Common Issues
1. LUKS/LVM Issues:
```bash
# Check LUKS status
cryptsetup status cryptroot
# Check LVM status
lvs
vgs
```

2. GPU Issues:
```bash
# Check NVIDIA driver
nvidia-smi
# Check Xorg logs
cat /var/log/Xorg.0.log
```

3. Development Environment Issues:
```bash
# Check PostgreSQL status
sudo systemctl status postgresql
# Check ZSH configuration
zsh --version
echo $SHELL
```

## Contributing
Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License
[MIT License](LICENSE)

## Acknowledgments
- Void Linux team
- BORE scheduler developers
- BBR3 developers
- Various open-source projects used in this script

## Security Considerations
- Full disk encryption
- Secure boot configuration
- AppArmor profiles
- Network security
- Access control

## Performance Optimization
- CPU frequency management
- GPU power management
- Storage I/O optimization
- Network stack tuning
- Memory management

## Support
For issues and questions:
1. Check the documentation
2. Search existing issues
3. Create a new issue