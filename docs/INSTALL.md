# 📦 Zing Installation Guide

This document covers different ways to install and manage Zing on your system.

---

## Quick Install (One-liner)

### Default Installation (from source)
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/install.sh | bash
```

---

## Manual Installation Methods

### 1. From Source (Recommended)

**Prerequisites:**
- Zig >= 0.16.0
- Git

**Steps:**
```bash
# Clone the repository
git clone https://github.com/ghostkellz/zing.git
cd zing

# Build with optimizations
zig build -Doptimize=ReleaseFast

# Install binary
sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing

# Verify installation
zing --version
```

### 2. Using PKGBUILD (Arch Linux)

```bash
# Clone and build package
git clone https://github.com/ghostkellz/zing.git
cd zing

# Build package
makepkg -si
```

### 3. From AUR (when available)

```bash
# Using yay
yay -S zing

# Using paru
paru -S zing
```

---

## Verification

After installation, verify Zing is working:

```bash
# Check version
zing version

# Show help
zing help

# Test project detection
zing detect
```

Expected output:
```
Zing v0.1.0 - Next-Generation Build & Packaging Engine
Built with Zig 0.16.0-dev
Copyright (c) 2024-2025 GhostKellz
Licensed under MIT License
```

---

## Updating

### From Source Installation
```bash
cd zing
git pull
zig build -Doptimize=ReleaseFast
sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing
```

---

## Uninstallation

### Manual Uninstallation

**For source installation:**
```bash
# Remove binary
sudo rm /usr/local/bin/zing

# Remove cache (optional)
rm -rf ~/.cache/zing
```

**For package installation:**
```bash
sudo pacman -Rs zing
```

---

## Troubleshooting

### Common Issues

#### "zig: command not found"
Install Zig from the official repositories:
```bash
sudo pacman -S zig
```

Or install a newer version from AUR:
```bash
yay -S zig-dev-bin
```

#### "Build failed" during compilation
Check Zig version and update if necessary:
```bash
zig version  # Should be >= 0.16.0

# Update system
sudo pacman -Syu

# Try building manually with verbose output
zig build -Doptimize=ReleaseFast --verbose
```

### Build Dependencies

Make sure these are installed before building:
```bash
sudo pacman -S --needed base-devel zig git
```

### Platform Support

Currently supported platforms:
- **x86_64**: Full support
- **aarch64**: Full support (ARM64)

### Cross-Compilation

You can also cross-compile Zing for different architectures:
```bash
# For ARM64
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu

# For Windows (if needed for development)
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows-gnu
```

---

## Development Installation

For development and contributing:

```bash
# Clone with development setup
git clone https://github.com/ghostkellz/zing.git
cd zing

# Build in debug mode
zig build

# Run tests
zig build test

# Run locally
./zig-out/bin/zing --help
```
