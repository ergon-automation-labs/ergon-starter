# Vagrant Providers — Multi-Platform Setup

Choose the right provider for your platform to run Bot Army Starter tests.

## Quick Reference

| Platform | Hypervisor | Provider | Status |
|----------|-----------|----------|--------|
| **macOS (Apple Silicon)** | Parallels Desktop | `parallels` | ✅ Primary |
| **macOS (Intel)** | VirtualBox | `virtualbox` | ✅ Supported |
| **Windows 10/11** | VirtualBox | `virtualbox` | ✅ Supported |
| **Linux (any)** | VirtualBox | `virtualbox` | ✅ Supported |
| **Linux (KVM)** | libvirt | `libvirt` | 🟡 Supported (manual setup) |

## Setup by Platform

### macOS with Apple Silicon (M1/M2/M3/M4)

**Best option:** Parallels Desktop (native ARM64 support)

```bash
# Prequisites
brew install vagrant parallels-desktop

# Or if you already have it:
vagrant plugin install vagrant-parallels

# Run
cd vagrant-test
make up        # Uses Parallels by default
make phase02
```

**Alternative:** VirtualBox (emulated, slower)
```bash
vagrant up --provider=virtualbox
```

---

### macOS (Intel CPU)

**Best option:** VirtualBox

```bash
# Prerequisites
brew install vagrant virtualbox

# Run
cd vagrant-test
vagrant up --provider=virtualbox
make phase02
```

---

### Windows 10/11

**Prerequisites:**
1. Install [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
2. Install [Vagrant](https://www.vagrantup.com/downloads)
3. Enable CPU virtualization in BIOS (may be required)

**Run:**
```bash
cd vagrant-test
vagrant up --provider=virtualbox
make phase02
```

**Troubleshooting:**
- If VirtualBox fails to boot: check BIOS for "VT-x" or "AMD-V" enabled
- If port forwarding fails: Windows Defender Firewall may block ports. Temporarily disable or add exception for VirtualBox.

---

### Linux (with VirtualBox)

**Prerequisites:**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install vagrant virtualbox virtualbox-dkms linux-headers-$(uname -r)

# Fedora
sudo dnf install vagrant VirtualBox

# Arch
sudo pacman -S vagrant virtualbox
```

**Run:**
```bash
cd vagrant-test
vagrant up --provider=virtualbox
make phase02
```

**Nested Virtualization (if running inside a VM):**
```bash
# Enable KVM nesting in your host VM settings
# Then, in Vagrantfile, uncomment the nested-hw-virt option
```

---

### Linux (with KVM/libvirt)

**Prerequisites:**
```bash
sudo apt install vagrant qemu-kvm libvirt-daemon

# Install vagrant-libvirt plugin
vagrant plugin install vagrant-libvirt
```

**Run:**
```bash
cd vagrant-test
vagrant up --provider=libvirt
make phase02
```

**Uncomment in Vagrantfile:**
```ruby
config.vm.provider "libvirt" do |lv|
  lv.memory = 8192
  lv.cpus   = 4
  lv.disk_bus = "virtio"
end
```

---

## Resource Requirements by Provider

| Provider | Min RAM | Min CPUs | Disk | Notes |
|----------|---------|----------|------|-------|
| **Parallels** | 12 GB | 4 | 40 GB | Host must have 24+ GB total |
| **VirtualBox** | 8 GB | 4 | 40 GB | Shared with host; may slow if host is RAM-constrained |
| **libvirt** | 8 GB | 4 | 40 GB | Native Linux; best performance on Linux hosts |

**Why these specs?**
- 8+ GB VM: Docker build + 12-bot stack + Ollama model pulls
- 4 CPUs: Parallel compilation, Docker layer caching
- 40 GB disk: Builds expand ~6 GB base to 30-40 GB with models

---

## Provider-Specific Issues

### Parallels (macOS)

**Issue:** "Parallels Tools not installed"
```bash
# Solution: vagrant up will install them automatically
# If stuck, manually:
vagrant reload
```

**Issue:** Port forwarding not working
```bash
# Check Parallels network settings
# Restart Parallels network:
sudo prlsrvctl net list
sudo prlsrvctl net stop Shared
sudo prlsrvctl net start Shared
```

### VirtualBox

**Issue:** "AMD-V is not supported" (Linux) or "VT-x not available" (Windows/Intel)
```bash
# Check BIOS:
# - Restart computer → BIOS setup (Del, F2, F12, etc.)
# - Find "Virtualization" or "VT-x" or "AMD-V"
# - Enable it
# - Reboot
```

**Issue:** "Host-only network not working"
```bash
# VirtualBox Host-only adapter may not exist
# Create one:
# 1. VirtualBox UI → Preferences → Network
# 2. Click "Create" under Host-only Networks
# 3. Re-run: vagrant up --provider=virtualbox
```

### libvirt (Linux)

**Issue:** "Connection refused" when running libvirt commands
```bash
# libvirtd may not be running
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
```

**Issue:** Permission denied on /dev/kvm
```bash
# Add your user to the kvm group
sudo usermod -aG kvm $(whoami)
# Log out and back in, or:
newgrp kvm
```

---

## Selecting Provider at Runtime

Default provider is **Parallels** (for macOS). Override:

```bash
# Use VirtualBox instead
vagrant up --provider=virtualbox

# Destroy and switch providers
vagrant destroy -f
vagrant up --provider=libvirt

# Set as default (in .vagrant.local or shell alias)
export VAGRANT_DEFAULT_PROVIDER=virtualbox
```

---

## Performance Comparison

| Aspect | Parallels | VirtualBox | libvirt |
|--------|-----------|-----------|---------|
| **Boot time** | Fast | Slow–Medium | Fast |
| **Build speed** | Native (fast) | Emulated (slow on M1/M2) | Native |
| **Port forwarding** | Reliable | Quirky | Reliable |
| **Memory usage** | Efficient | High | Efficient |
| **Best for** | macOS/M1+ | Windows/Intel | Linux |

---

## See Also

- `Vagrantfile` — Provider configs
- `PORTMAP.md` — Port forwarding details
- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [VirtualBox Documentation](https://www.virtualbox.org/wiki/Documentation)
- [Parallels Vagrant Plugin](https://parallels.github.io/vagrant-parallels/)
