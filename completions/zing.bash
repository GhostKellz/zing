# zing bash completion script

_zing() {
    local cur prev commands targets
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="help version init build package clean detect compile cross"
    targets="x86_64-linux-gnu x86_64-linux-musl x86_64-windows-gnu x86_64-macos aarch64-linux-gnu aarch64-linux-musl aarch64-macos arm-linux-gnueabihf riscv64-linux-gnu wasm32-wasi"

    case "$prev" in
        zing)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            return 0
            ;;
        build|package)
            COMPREPLY=($(compgen -f -X '!*PKGBUILD*' -- "$cur"))
            return 0
            ;;
        compile)
            COMPREPLY=($(compgen -W "--release" -- "$cur"))
            return 0
            ;;
        cross)
            COMPREPLY=($(compgen -W "$targets" -- "$cur"))
            return 0
            ;;
    esac

    COMPREPLY=($(compgen -W "$commands --release" -- "$cur"))
}

complete -F _zing zing
