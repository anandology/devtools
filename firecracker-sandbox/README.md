# Firecracker VM Management Framework

A lightweight, developer-friendly framework for managing Firecracker VMs with sudo-less daily operations.

## Features

- **One-time system setup** with minimal friction
- **Easy VM creation** from templates
- **Sudo-less daily operations** (start/stop/ssh) after initial setup
- **Multiple simultaneous VMs** with bridge networking
- **Ubuntu 24.04** base images with customizable packages
- **Fast boot times** (~1 second after first boot)
- **First-boot automation** for package installation (APT + Nix)
- **Clean uninstall** path - complete removal when no longer needed

## Quick Start

### Prerequisites

- Ubuntu 22.04/24.04 host (or compatible Linux with KVM support)
- KVM enabled (`/dev/kvm` accessible)
- Required tools: `debootstrap`, `curl`, `ip`, `iptables`

```bash
sudo apt install debootstrap curl iproute2 iptables
```

### Installation

Extract the framework to `~/vms/`:

```bash
unzip vms.zip -d ~/
cd ~/vms
```

### Global Setup (One-time)

Set up the bridge network and install Firecracker:

```bash
sudo bin/setup.sh
```

This creates:
- Bridge network `br-firecracker` at `172.16.0.1/24`
- NAT rules for internet access
- Systemd service (auto-starts on boot)
- Downloads Firecracker binary

## Usage

### Create a New VM

#### 1. Initialize Configuration

```bash
~/vms/vm.sh init myvm
```

This creates:
- `~/vms/vms/myvm/config.sh` - VM configuration
- `~/vms/vms/myvm/apt-packages.txt` - APT packages to install
- `~/vms/vms/myvm/packages.nix` - Nix packages to install
- Auto-assigns IP address (e.g., `172.16.0.2`)

#### 2. Edit Configuration (Optional)

```bash
vim ~/vms/vms/myvm/config.sh
```

Customize:
- `CPUS` - Number of vCPUs (default: 4)
- `MEMORY` - RAM in MB (default: 8192)
- `ROOTFS_SIZE` - Root filesystem size (default: 8G)
- `HOME_SIZE` - Home volume size (default: 20G)
- `USERNAME` - Username (auto-detected)
- `SSH_KEY_PATH` - SSH public key path (auto-detected)

Edit packages:
```bash
vim ~/vms/vms/myvm/apt-packages.txt  # One package per line
vim ~/vms/vms/myvm/packages.nix      # Space-separated Nix packages
```

#### 3. Build VM

```bash
sudo ~/vms/vm.sh build myvm
```

This creates:
- Minimal Ubuntu rootfs with `debootstrap`
- User account with SSH key
- Network configuration
- Persistent TAP device (owned by your user)
- Home volume

#### 4. Start VM

```bash
~/vms/vm.sh up myvm
```

First boot installs packages (takes a few minutes). Subsequent boots are fast (~1 second).

### Daily Operations

All commands run **without sudo**:

```bash
# Start VM (background mode)
~/vms/vm.sh up myvm

# Start VM with console access (for troubleshooting)
~/vms/vm.sh console myvm

# SSH into VM
~/vms/vm.sh ssh myvm

# Check status
~/vms/vm.sh status myvm

# List all VMs
~/vms/vm.sh list

# Stop VM
~/vms/vm.sh down myvm
```

### Advanced SSH

```bash
# Run a command
~/vms/vm.sh ssh myvm "ls -la"

# Port forwarding
~/vms/vm.sh ssh myvm -L 5432:localhost:5432

# Direct SSH (if you prefer)
ssh <username>@172.16.0.2
```

### VM Management

```bash
# Destroy VM (requires sudo for TAP removal)
sudo ~/vms/vm.sh destroy myvm

# Cleanup entire framework (requires sudo)
sudo bin/cleanup.sh
```

## VM Lifecycle

```
┌──────────┐
│   init   │  Create configuration (no sudo)
└────┬─────┘
     │
┌────▼─────┐
│  build   │  Build rootfs, create TAP (requires sudo)
└────┬─────┘
     │
┌────▼─────┐
│    up    │  Start VM (no sudo)
└────┬─────┘
     │
┌────▼─────┐
│ running  │  Daily operations (no sudo)
└────┬─────┘
     │
┌────▼─────┐
│   down   │  Stop VM (no sudo)
└────┬─────┘
     │
┌────▼─────┐
│ destroy  │  Remove VM (requires sudo)
└──────────┘
```

## Network Architecture

```
┌─────────────────────────────────────────┐
│ Host (172.16.0.1)                       │
│                                         │
│  ┌────────────────────────────────┐    │
│  │ br-firecracker                 │    │
│  │  172.16.0.1/24                 │    │
│  └──────┬──────┬──────┬───────────┘    │
│         │      │      │                 │
│    ┌────▼─┐ ┌─▼────┐ ┌▼─────┐         │
│    │tap-1 │ │tap-2 │ │tap-3 │         │
│    └──────┘ └──────┘ └──────┘         │
│         │      │      │                 │
└─────────┼──────┼──────┼─────────────────┘
          │      │      │
     ┌────▼──┐ ┌▼────┐ ┌▼─────┐
     │ VM 1  │ │VM 2 │ │ VM 3 │
     │.0.2   │ │.0.3 │ │.0.4  │
     └───────┘ └─────┘ └──────┘
```

- Each VM has a dedicated TAP device owned by your user
- All VMs share the bridge network
- NAT provides internet access
- VMs can communicate with each other

## Directory Structure

```
~/vms/
├── vm.sh                    # Main CLI
├── bin/                     # Framework scripts
│   ├── config.sh            # Global configuration
│   ├── setup.sh             # System setup
│   ├── cleanup.sh           # System cleanup
│   ├── vm-init.sh           # Initialize VM
│   ├── vm-build.sh          # Build VM
│   ├── vm-up.sh             # Start VM (background)
│   ├── vm-console.sh        # Start VM with console
│   ├── vm-down.sh           # Stop VM
│   ├── vm-ssh.sh            # SSH to VM
│   ├── vm-status.sh         # VM status
│   ├── vm-list.sh           # List VMs
│   ├── vm-destroy.sh        # Destroy VM
│   └── first-boot.sh        # First-boot automation
├── kernels/                 # Shared kernels (auto-downloaded)
│   └── vmlinux-6.1.102
├── state/                   # Framework state
│   └── bridge -> /sys/class/net/br-firecracker
└── vms/                     # VM instances
    └── myvm/
        ├── config.sh        # VM configuration
        ├── apt-packages.txt # APT packages
        ├── packages.nix     # Nix packages
        ├── rootfs.ext4      # Root filesystem
        ├── home.ext4        # Home volume
        ├── ssh_key.pub      # Cached SSH key
        └── state/
            ├── ip.txt       # Assigned IP
            ├── tap_name.txt # TAP device name
            ├── vm.pid       # Process ID (when running)
            └── console.log  # VM console output
```

## Customization

### Default Packages

Edit after `vm.sh init`:

**APT packages** (`apt-packages.txt`):
```
podman
postgresql
tmux
vim
git
curl
htop
ripgrep
```

**Nix packages** (`packages.nix`):
```
go_1_24 nodejs
```

### Resource Configuration

Edit `config.sh` after init:

```bash
CPUS=8              # More CPU cores
MEMORY=16384        # 16 GB RAM
ROOTFS_SIZE="20G"   # Larger root filesystem
HOME_SIZE="50G"     # Larger home volume
```

Then rebuild:
```bash
sudo ~/vms/vm.sh destroy myvm
sudo ~/vms/vm.sh build myvm
```

## Troubleshooting

### Cannot access /dev/kvm

Add your user to the `kvm` group:
```bash
sudo usermod -aG kvm $USER
# Log out and back in
```

### Bridge not found

Run setup again:
```bash
sudo bin/setup.sh
```

### VM won't start or login fails

Use console mode for interactive troubleshooting:
```bash
~/vms/vm.sh console myvm
```

This gives you direct console access to see boot messages and login directly.

You can also check the console log:
```bash
tail -f ~/vms/vms/myvm/state/console.log
```

Or mount the rootfs to inspect/fix files:
```bash
sudo mkdir -p /mnt/rootfs
sudo mount ~/vms/vms/myvm/rootfs.ext4 /mnt/rootfs
# Make changes...
sudo umount /mnt/rootfs
```

### SSH connection refused

Wait a few seconds after `vm.sh up`. VM needs time to boot.

### Stale PID file

Clean up:
```bash
~/vms/vm.sh down myvm
```

## Advanced Topics

### Multiple VMs

Create and run multiple VMs simultaneously:

```bash
~/vms/vm.sh init vm1
~/vms/vm.sh init vm2
~/vms/vm.sh init vm3

sudo ~/vms/vm.sh build vm1
sudo ~/vms/vm.sh build vm2
sudo ~/vms/vm.sh build vm3

~/vms/vm.sh up vm1
~/vms/vm.sh up vm2
~/vms/vm.sh up vm3

~/vms/vm.sh list
```

### Inter-VM Communication

VMs can communicate directly:

```bash
# From vm1
ssh user@172.16.0.3  # Connect to vm2
ping 172.16.0.4      # Ping vm3
```

### Persistent Data

The home volume (`home.ext4`) persists across VM restarts. Mount it in the VM:

```bash
sudo mkdir -p /mnt/home
sudo mount /dev/vdb /mnt/home
```

Add to `/etc/fstab` for automatic mounting:
```
/dev/vdb  /mnt/home  ext4  defaults  0  2
```

## Uninstalling

Remove all VMs and the framework:

```bash
sudo bin/cleanup.sh
```

This removes:
- All VM instances
- Bridge network
- Systemd service
- TAP devices
- State directory

## Design Philosophy

1. **Sudo separation**: One-time privileged setup, daily operations without sudo
2. **Persistent TAP devices**: User-owned for sudo-less VM management
3. **Bridge networking**: Multiple VMs with direct IP communication
4. **Fast boot**: Minimal base image, first-boot automation for packages
5. **Clean abstractions**: Simple CLI, specialized scripts

## Credits

Built on [Firecracker](https://firecracker-microvm.github.io/) - AWS's lightweight virtualization technology.

## License

MIT

## Support

For issues and questions, see the design document at `design.md`.
