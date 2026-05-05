# Zing Installation

## Prerequisites

- Zig 0.16.0-dev or newer compatible with this repository
- Git
- Linux userland tools used by the current implementation such as `bash`, `tar`, and `zstd`

## Build From Source

```bash
git clone https://github.com/ghostkellz/zing.git
cd zing
zig build -Doptimize=ReleaseFast
sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing
```

## Verify

```bash
zing version
zing help
zing detect
```

Expected version output:

```text
Zing v0.1.0 - Next-Generation Build & Packaging Engine
Copyright (c) 2024-2025 GhostKellz
Licensed under MIT License
```

## Arch Packaging Files

The repository does not ship a top-level `PKGBUILD`.

Use:

- `release/arch/PKGBUILD`
- `release/arch/install.sh`

## Development Workflow

```bash
zig build
zig build test
./zig-out/bin/zing help
```

## Cleanup

The current PKGBUILD flow uses a local `.zing-cache` directory for cached sources and `.zing-work` for transient build state.

To remove generated local artifacts:

```bash
rm -rf .zing-cache .zing-work zig-out .zig-cache
```
