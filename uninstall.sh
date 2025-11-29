#!/bin/bash
# Zing uninstall script
# Usage: ./uninstall.sh

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

# Remove files installed by different methods
uninstall_zing() {
    info "Uninstalling zing..."

    local removed_something=false

    # Check for pacman-installed zing
    if pacman -Q zing &> /dev/null; then
        info "Removing zing package..."
        sudo pacman -Rs zing
        removed_something=true
    fi

    # Check for manually installed zing in /usr/local/bin
    if [[ -f "/usr/local/bin/zing" ]]; then
        info "Removing /usr/local/bin/zing..."
        sudo rm -f /usr/local/bin/zing
        removed_something=true
    fi

    # Remove documentation
    if [[ -d "/usr/local/share/doc/zing" ]]; then
        info "Removing documentation..."
        sudo rm -rf /usr/local/share/doc/zing
        removed_something=true
    fi

    # Remove cache directory (optional)
    local cache_dir="$HOME/.cache/zing"
    if [[ -d "$cache_dir" ]]; then
        read -p "Remove cache directory ($cache_dir)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Removing cache directory..."
            rm -rf "$cache_dir"
            removed_something=true
        fi
    fi

    if [[ "$removed_something" == true ]]; then
        success "zing has been uninstalled"
    else
        warning "No zing installation found to remove"
    fi
}

# Main uninstall logic
main() {
    info "🗑️  Zing uninstaller"
    echo

    # Parse command line arguments
    local force_remove=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_remove=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --force      Force removal without confirmation"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Confirm uninstallation
    if [[ "$force_remove" != true ]]; then
        echo "This will remove zing and its associated files."
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Uninstallation cancelled"
            exit 0
        fi
    fi

    # Uninstall zing
    uninstall_zing

    # Verify removal
    if ! command -v zing &> /dev/null; then
        success "zing has been completely removed"
    else
        warning "zing command still found in PATH - manual cleanup may be required"
    fi
}

# Run main function with all arguments
main "$@"
