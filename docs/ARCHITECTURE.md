# Zing Architecture

## Overview

The current codebase is organized around three primary paths:

- `src/main.zig`: CLI entrypoint and command dispatch
- `src/parser.zig` + `src/builder.zig`: PKGBUILD parsing and execution
- `src/native.zig`: Zig/C/C++ project detection and compilation

## PKGBUILD Path

`zing build` and `zing package` follow this flow:

1. Read the target `PKGBUILD`
2. Parse a limited metadata subset in `src/parser.zig`
3. Build a `BuildContext` in `src/builder.zig`
4. Preflight `depends` and `makedepends` against the local pacman database when available
5. Stage sources under `.zing-work/src/` and cache downloads under `.zing-cache/`
6. Run `prepare()`, `build()`, and `check()` if present
7. For `zing package`, run `package()`, archive `.zing-work/pkg/`, and verify the resulting package metadata

This path is intentionally simple. It is not yet a full `makepkg` implementation.

## Native Build Path

`src/native.zig` detects projects by scanning the target directory for:

- `build.zig` or `.zig` files
- `.c` files
- `.cpp`, `.cc`, or `.cxx` files

Based on the result:

- Zig projects run `zig build`
- C and C++ projects run `zig cc`
- Mixed projects are detected but not fully supported by the CLI

## Supporting Modules

Additional modules exist for future or partial functionality:

- `src/cache.zig`
- `src/deps.zig`
- `src/packager.zig`
- `src/aur.zig`
- `src/multiarch.zig`
- `src/zmk.zig`

Current state:

- `src/deps.zig` is wired into the PKGBUILD flow for local dependency preflight
- `src/packager.zig` is wired into `zing package`
- `src/aur.zig`, `src/cache.zig`, `src/multiarch.zig`, and `src/zmk.zig` remain incomplete and are not exposed by the CLI

## Testing

The project now includes focused unit coverage for:

- parser field parsing and validation
- PKGBUILD function extraction
- native project detection and metadata parsing

`zig build test` is the baseline verification target.
