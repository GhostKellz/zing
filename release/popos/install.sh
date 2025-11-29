#!/bin/bash
# Zing installer for Pop!_OS (COSMIC Desktop)
# Usage: curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/popos/install.sh | bash

set -euo pipefail

# Colors - COSMIC-inspired palette
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; exit 1; }
cosmic()  { echo -e "${MAGENTA}${BOLD}[COSMIC]${NC} $1"; }

# Check if running as root
[[ $EUID -eq 0 ]] && error "This script should not be run as root"

# Check for Pop!_OS / Ubuntu base
command -v apt &>/dev/null || error "This installer requires apt"

echo -e "${MAGENTA}${BOLD}"
cat << 'EOF'
    ╔══════════════════════════════════════╗
    ║  🚀 Zing Installer for Pop!_OS       ║
    ║     Optimized for COSMIC Desktop     ║
    ╚══════════════════════════════════════╝
EOF
echo -e "${NC}"

# Detect distro and desktop
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    info "Detected: $PRETTY_NAME"
fi

# Check for COSMIC desktop
if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    if [[ "$XDG_CURRENT_DESKTOP" == *"COSMIC"* ]] || [[ "$XDG_CURRENT_DESKTOP" == *"cosmic"* ]]; then
        cosmic "COSMIC Desktop detected! 🌌"
    elif [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
        info "GNOME Desktop detected (Pop!_OS classic)"
    fi
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

    # Add to PATH for bash
    if ! grep -q '/opt/zig' ~/.bashrc 2>/dev/null; then
        echo 'export PATH="/opt/zig:$PATH"' >> ~/.bashrc
    fi

    # Add to PATH for fish (common on Pop!_OS)
    if [[ -d ~/.config/fish ]]; then
        mkdir -p ~/.config/fish/conf.d
        echo 'set -gx PATH /opt/zig $PATH' > ~/.config/fish/conf.d/zig.fish
        cosmic "Fish shell config updated"
    fi

    # Add to PATH for zsh
    if [[ -f ~/.zshrc ]]; then
        if ! grep -q '/opt/zig' ~/.zshrc 2>/dev/null; then
            echo 'export PATH="/opt/zig:$PATH"' >> ~/.zshrc
        fi
    fi

    export PATH="/opt/zig:$PATH"

    rm -f "zig-linux-${ARCH}-${ZIG_VERSION}.tar.xz"

    success "Zig installed to /opt/zig"
}

# Install icons for all desktop environments
install_icons() {
    local ICON_DIR="/usr/local/share/icons/hicolor"

    info "Installing icons..."
    for size in 16 24 32 48 64 128 256 512; do
        sudo mkdir -p "${ICON_DIR}/${size}x${size}/apps"
        if [[ -f "release/shared/icons/zing-${size}.png" ]]; then
            sudo cp "release/shared/icons/zing-${size}.png" "${ICON_DIR}/${size}x${size}/apps/zing.png"
        fi
    done

    # Update icon cache for GTK (GNOME)
    if command -v gtk-update-icon-cache &>/dev/null; then
        sudo gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true
    fi

    # COSMIC uses a different icon system - it should pick up hicolor icons automatically
    # but we can also place in the COSMIC-specific location if it exists
    if [[ -d "/usr/share/cosmic/icons" ]]; then
        cosmic "Installing COSMIC-specific icons..."
        for size in 16 24 32 48 64 128 256; do
            sudo mkdir -p "/usr/share/cosmic/icons/${size}x${size}/apps"
            if [[ -f "release/shared/icons/zing-${size}.png" ]]; then
                sudo cp "release/shared/icons/zing-${size}.png" "/usr/share/cosmic/icons/${size}x${size}/apps/zing.png"
            fi
        done
    fi

    success "Icons installed"
}

# Check dependencies
info "Checking dependencies..."

# Install required packages
PKGS=()
command -v git &>/dev/null || PKGS+=("git")
command -v curl &>/dev/null || PKGS+=("curl")
command -v xz &>/dev/null || PKGS+=("xz-utils")

if [[ ${#PKGS[@]} -gt 0 ]]; then
    info "Installing: ${PKGS[*]}"
    sudo apt update
    sudo apt install -y "${PKGS[@]}"
fi

# Check for Zig
if ! command -v zig &>/dev/null; then
    warning "Zig not found"
    echo -n "Install Zig? [Y/n] "
    read -r REPLY
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

# Update desktop database
if command -v update-desktop-database &>/dev/null; then
    sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true
fi

# Verify
echo
if command -v zing &>/dev/null; then
    success "Zing installed successfully!"
    echo
    zing --version
    echo
    info "Run 'zing help' to get started"
    echo
    cosmic "Enjoy building with Zing on Pop!_OS! 🚀"
    echo -e "${MAGENTA}${BOLD}Welcome to the COSMIC era of builds!${NC}"
else
    error "Installation failed"
fi
