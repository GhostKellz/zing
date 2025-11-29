# zmake bash completion script
# Install to: /usr/share/bash-completion/completions/zmake

_zmake() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    local commands="help version init build package clean detect compile cross zmk-init zmk-build aur-search aur-install multi-build cache-stats"
    
    # Global options
    local global_opts="--help -h --version -v --verbose --quiet --no-cache --cache-size"
    
    # Command-specific options
    local build_opts="--force --no-deps --no-cache"
    local compile_opts="--release --debug --target --output"
    local cross_opts="--release --features"
    local package_opts="--sign --output --compression"
    local clean_opts="--all --cache-only --builds-only"
    local multi_build_opts="--parallel --release --output"
    local zmk_build_opts="--target --no-aur"
    local aur_install_opts="--no-deps --force --dry-run"

    # Target triples for cross-compilation
    local targets="x86_64-linux-gnu x86_64-linux-musl x86_64-windows-gnu x86_64-macos aarch64-linux-gnu aarch64-linux-musl aarch64-macos arm-linux-gnueabihf riscv64-linux-gnu wasm32-wasi wasm32-freestanding"
    
    # Multi-build target sets
    local target_sets="desktop embedded web all"

    case $prev in
        zmake)
            COMPREPLY=($(compgen -W "$commands $global_opts" -- "$cur"))
            return 0
            ;;
        build)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$build_opts" -- "$cur"))
            else
                # Complete PKGBUILD files
                COMPREPLY=($(compgen -f -X '!*PKGBUILD*' -- "$cur"))
            fi
            return 0
            ;;
        package)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$package_opts" -- "$cur"))
            else
                COMPREPLY=($(compgen -f -X '!*PKGBUILD*' -- "$cur"))
            fi
            return 0
            ;;
        compile)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$compile_opts" -- "$cur"))
            else
                COMPREPLY=($(compgen -d -- "$cur"))
            fi
            return 0
            ;;
        cross)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$cross_opts" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$targets" -- "$cur"))
            fi
            return 0
            ;;
        multi-build)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$multi_build_opts" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$target_sets" -- "$cur"))
            fi
            return 0
            ;;
        zmk-build)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$zmk_build_opts" -- "$cur"))
            else
                # Complete .toml files
                COMPREPLY=($(compgen -f -X '!*.toml' -- "$cur"))
            fi
            return 0
            ;;
        aur-search|aur-install)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$aur_install_opts" -- "$cur"))
            fi
            return 0
            ;;
        clean)
            COMPREPLY=($(compgen -W "$clean_opts" -- "$cur"))
            return 0
            ;;
        detect)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        zmk-init)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        init)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        --target)
            COMPREPLY=($(compgen -W "$targets" -- "$cur"))
            return 0
            ;;
        --cache-size)
            COMPREPLY=($(compgen -W "50 100 200 500 1000" -- "$cur"))
            return 0
            ;;
        --parallel)
            COMPREPLY=($(compgen -W "1 2 4 8 16" -- "$cur"))
            return 0
            ;;
        --compression)
            COMPREPLY=($(compgen -W "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22" -- "$cur"))
            return 0
            ;;
        --output)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        --sign)
            # Complete GPG keys (simplified - could be enhanced)
            local gpg_keys=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/uid:/ {print $10}' | head -10)
            COMPREPLY=($(compgen -W "$gpg_keys" -- "$cur"))
            return 0
            ;;
    esac

    # Default completion for files and directories
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$global_opts" -- "$cur"))
    else
        COMPREPLY=($(compgen -f -- "$cur"))
    fi
}

# Register completion
complete -F _zmake zmake