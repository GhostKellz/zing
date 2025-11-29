#!/bin/bash
# Zing installer for Fedora / Nobara / Bazzite
# Usage: curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/fedora/install.sh | bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}${BOLD}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
[[ $EUID -eq 0 ]] && error "This script should not be run as root"

# Check for Fedora/RPM-based system
command -v dnf &>/dev/null || command -v yum &>/dev/null || error "This installer requires dnf/yum"

# Detect package manager
PKG_MGR="dnf"
command -v dnf &>/dev/null || PKG_MGR="yum"

info "🚀 Zing Installer for Fedora / Nobara / Bazzite"
echo

# Detect distro
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    info "Detected: $PRETTY_NAME"
fi

# Install Zig
install_zig() {
    info "Installing Zig..."

    local ZIG_VERSION="0.14.0"
    local ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="x86_64" ;;
        aarch64) ARCH="aarch64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    local ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-${ARCH}-${ZIG_VERSION}.tar.xz"

    cd /tmp
    info "Downloading Zig..."
    curl -LO "$ZIG_URL"

    info "Extracting Zig..."
    sudo mkdir -p /opt/zig
    sudo tar -xf "zig-linux-${ARCH}-${ZIG_VERSION}.tar.xz" -C /opt/zig --strip-components=1

    # Add to PATH
    if ! grep -q '/opt/zig' ~/.bashrc 2>/dev/null; then
        echo 'export PATH="/opt/zig:$PATH"' >> ~/.bashrc
    fi
    export PATH="/opt/zig:$PATH"

    rm -f "zig-linux-${ARCH}-${ZIG_VERSION}.tar.xz"

    success "Zig installed to /opt/zig"
}

# Install icons helper
install_icons() {
    local ICON_DIR="/usr/local/share/icons/hicolor"

    for size in 16 24 32 48 64 128 256 512; do
        sudo mkdir -p "${ICON_DIR}/${size}x${size}/apps"
        if [[ -f "release/shared/icons/zing-${size}.png" ]]; then
            sudo cp "release/shared/icons/zing-${size}.png" "${ICON_DIR}/${size}x${size}/apps/zing.png"
        fi
    done

    # Update icon cache
    command -v gtk-update-icon-cache &>/dev/null && sudo gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true
}

# Check dependencies
info "Checking dependencies..."

# Install git if needed
if ! command -v git &>/dev/null; then
    info "Installing git..."
    sudo $PKG_MGR install -y git
fi

# Install curl and xz if needed
command -v curl &>/dev/null || sudo $PKG_MGR install -y curl
command -v xz &>/dev/null || sudo $PKG_MGR install -y xz

# Check for Zig
if ! command -v zig &>/dev/null; then
    warning "Zig not found"
    read -p "Install Zig? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_zig
    else
        error "Zig is required to build zing"
    fi
fi

info "Using Zig: $(zig version)"

# Install zing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
info "Cloning zing..."
git clone --depth 1 https://github.com/ghostkellz/zing.git
cd zing

info "Building zing..."
zig build -Doptimize=ReleaseFast

info "Installing..."
sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing

# Install documentation
sudo mkdir -p /usr/local/share/doc/zing
sudo cp README.md /usr/local/share/doc/zing/
[[ -d docs ]] && sudo cp docs/*.md /usr/local/share/doc/zing/ 2>/dev/null || true

# Install desktop file
sudo mkdir -p /usr/local/share/applications
sudo cp release/shared/desktop/zing.desktop /usr/local/share/applications/

# Install icons
install_icons

# Verify
if command -v zing &>/dev/null; then
    success "Zing installed successfully!"
    echo
    zing --version
    echo
    info "Run 'zing help' to get started"
else
    error "Installation failed"
fi
