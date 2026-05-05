<p align="center">
  <img src="assets/logo/zing.png" alt="Zing logo" width="200"/>
</p>

<h1 align="center">Zing</h1>

<p align="center">
  <strong>A Zig-based PKGBUILD and native project helper</strong>
</p>

## Overview

`zing` is a small Zig CLI for two workflows:

- Running simple PKGBUILD-style `prepare()`, `build()`, `check()`, and `package()` functions
- Detecting and compiling native Zig, C, and C++ projects with `zig build` or `zig cc`

The project currently targets Linux-first development and is still early-stage. The implemented surface is useful, but narrower than a full `makepkg` replacement.

## Current Capabilities

- Parse a limited set of PKGBUILD fields: `pkgname`, `pkgver`, `pkgrel`, `pkgdesc`, `arch`, `url`, `license`, `depends`, `makedepends`, `source`, `sha256sums`
- Execute PKGBUILD `prepare()`, `build()`, `check()`, and `package()` functions through `bash`
- Preflight `depends` and `makedepends` against the local pacman database when available
- Create a basic `.pkg.tar.zst` archive with `.PKGINFO` and `.MTREE`
- Detect Zig, C, C++, and mixed-source repositories
- Compile Zig projects with `zig build`
- Compile C and C++ projects with `zig cc`
- Cross-compile by passing a Zig target triple to `zing cross`

## Current Gaps

- PKGBUILD parsing is intentionally incomplete and does not aim at full `makepkg` compatibility yet
- AUR integration, cache reuse, signing, and multi-arch packaging are still incomplete or only partially implemented
- Some supporting modules exist in the repo as future work and are not exposed by the current CLI

## Install

```bash
git clone https://github.com/ghostkellz/zing.git
cd zing
zig build -Doptimize=ReleaseFast
sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing
```

Arch packaging files live under `release/arch/`.

## Quick Start

### PKGBUILD workflow

```bash
zing init
zing build
zing package
zing clean
```

PKGBUILD runs stage transient work under `.zing-work/` and cache downloaded sources under `.zing-cache/` next to the target `PKGBUILD`.

### Native project workflow

```bash
zing detect
zing compile
zing cross x86_64-windows-gnu --release
```

## Project Layout

```text
zing/
├── src/
├── docs/
├── examples/
├── release/
└── build.zig
```

## Documentation

- `docs/COMMANDS.md`
- `docs/INSTALL.md`
- `docs/ARCHITECTURE.md`

## License

MIT. See `LICENSE`.
