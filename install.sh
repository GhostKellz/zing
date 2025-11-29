#!/bin/bash
# Zing installer script - One-liner installer for Zing
# Usage: curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/install.sh | bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error "This script should not be run as root"
fi

# Check if we're on Arch Linux
if ! command -v pacman &> /dev/null; then
    error "This installer is designed for Arch Linux systems with pacman"
fi

# Check for required dependencies
check_dependencies() {
    info "Checking dependencies..."

    local missing_deps=()

    # Check for Zig
    if ! command -v zig &> /dev/null; then
        missing_deps+=("zig")
    else
        local zig_version=$(zig version)
        info "Found Zig: $zig_version"

        # Check if Zig version is >= 0.16.0
        if [[ $(echo "$zig_version" | cut -d. -f1-2) < "0.16" ]]; then
            warning "Zig version $zig_version may be too old (need >= 0.16.0)"
        fi
    fi

    # Check for git
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi

    # Install missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        info "Installing missing dependencies: ${missing_deps[*]}"
        sudo pacman -S --needed "${missing_deps[@]}"
    fi
}

# Install zing from source
install_from_source() {
    local temp_dir="$1"

    info "Installing zing from source..."

    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Clone repository
    info "Cloning zing repository..."
    git clone https://github.com/ghostkellz/zing.git
    cd zing

    # Build zing
    info "Building zing with Zig..."
    zig build -Doptimize=ReleaseFast

    # Install binary
    info "Installing zing to /usr/local/bin..."
    sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing

    # Install documentation
    sudo mkdir -p /usr/local/share/doc/zing
    sudo cp README.md /usr/local/share/doc/zing/
    if [[ -d "docs" ]]; then
        sudo cp docs/*.md /usr/local/share/doc/zing/ 2>/dev/null || true
    fi

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    success "zing installed to /usr/local/bin/zing"
}

# Install from AUR
install_from_aur() {
    info "Installing zing from AUR..."

    if command -v yay &> /dev/null; then
        yay -S zing
    elif command -v paru &> /dev/null; then
        paru -S zing
    else
        warning "No AUR helper found. Installing from source instead..."
        install_from_source "/tmp/zing-install-$$"
    fi
}

# Main installation logic
main() {
    info "🚀 Zing installer - Next-Generation Build & Packaging Engine"
    echo

    # Parse command line arguments
    local install_method="source"
    local force_install=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --aur)
                install_method="aur"
                shift
                ;;
            --source)
                install_method="source"
                shift
                ;;
            --force)
                force_install=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --source     Install from source (default)"
                echo "  --aur        Install from AUR"
                echo "  --force      Force reinstall even if already installed"
                echo "  --help       Show this help message"
                echo
                echo "Examples:"
                echo "  curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/install.sh | bash"
                echo "  curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/install.sh | bash -s -- --aur"
                exit 0
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Check if zing is already installed
    if command -v zing &> /dev/null && [[ "$force_install" != true ]]; then
        local current_version=$(zing version 2>/dev/null | head -n1 || echo "unknown")
        warning "zing is already installed: $current_version"
        echo "Use --force to reinstall or run 'zing version' to check your installation"
        exit 0
    fi

    # Check dependencies
    check_dependencies

    # Install zing
    case "$install_method" in
        "source")
            install_from_source "/tmp/zing-install-$$"
            ;;
        "aur")
            install_from_aur
            ;;
    esac

    # Verify installation
    info "Verifying installation..."
    if command -v zing &> /dev/null; then
        local version=$(zing version 2>/dev/null | head -n1 || echo "unknown")
        success "Installation successful! $version"
        echo
        info "🎉 zing is now ready to use!"
        echo
        echo "Try these commands to get started:"
        echo "  zing help                    # Show help"
        echo "  zing init                    # Initialize a PKGBUILD workspace"
        echo "  zing detect                  # Auto-detect project type"
        echo "  zing compile --release       # Compile native project"
        echo
        echo "📚 Documentation: /usr/local/share/doc/zing/"
        echo "🔗 Repository: https://github.com/ghostkellz/zing"
    else
        error "Installation failed - zing command not found"
    fi
}

# Handle script interruption
trap 'error "Installation interrupted"' INT TERM

# Run main function with all arguments
main "$@"
