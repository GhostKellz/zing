#!/bin/bash
# Zing installer for Arch Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/release/arch/install.sh | bash

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

# Check for Arch Linux
command -v pacman &>/dev/null || error "This installer requires pacman (Arch Linux)"

info "🚀 Zing Installer for Arch Linux"
echo

# Check/install dependencies
info "Checking dependencies..."
DEPS=()
command -v zig &>/dev/null || DEPS+=("zig")
command -v git &>/dev/null || DEPS+=("git")

if [[ ${#DEPS[@]} -gt 0 ]]; then
    info "Installing: ${DEPS[*]}"
    sudo pacman -S --needed --noconfirm "${DEPS[@]}"
fi

# Check Zig version
ZIG_VER=$(zig version | cut -d. -f1-2)
if [[ "$ZIG_VER" < "0.16" ]]; then
    warning "Zig $ZIG_VER may be too old. Zing requires Zig 0.16+"
fi

# Install
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
sudo mkdir -p /usr/local/share/doc/zing
sudo cp README.md /usr/local/share/doc/zing/
[[ -d docs ]] && sudo cp docs/*.md /usr/local/share/doc/zing/ 2>/dev/null || true

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
