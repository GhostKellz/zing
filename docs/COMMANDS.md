# 📋 Zing Commands Reference

Complete reference for all Zing commands, options, and usage patterns.

---

## General Usage

### Basic Syntax
```bash
zing <COMMAND> [OPTIONS] [ARGUMENTS]
```

### Global Options
```bash
--help, -h          Show help message
--version, -v       Show version information
```

### Environment Variables
```bash
ZING_CACHE_DIR      Custom cache directory (default: ~/.cache/zing)
```

---

## PKGBUILD Commands

Traditional PKGBUILD-based package building compatible with makepkg.

### `zing init`
Initialize a new build workspace with example PKGBUILD.

```bash
zing init
```

**Output:**
```
🚀 Initializing zing workspace...
✅ Created example PKGBUILD
📝 Edit the PKGBUILD file and run 'zing build' to get started!
```

### `zing build`
Build a package from PKGBUILD.

```bash
zing build [PKGBUILD_PATH]
```

**Options:**
- `PKGBUILD_PATH` - Path to PKGBUILD file (default: ./PKGBUILD)

**Examples:**
```bash
zing build                           # Build ./PKGBUILD
zing build /path/to/PKGBUILD        # Build specific PKGBUILD
```

### `zing package`
Build and create .pkg.tar.zst package archive.

```bash
zing package [PKGBUILD_PATH]
```

**Examples:**
```bash
zing package                        # Build and package
zing package /path/to/PKGBUILD     # Package specific PKGBUILD
```

### `zing clean`
Clean build artifacts and cache.

```bash
zing clean
```

---

## Native Compilation

Direct compilation of Zig, C, and C++ projects without PKGBUILD.

### `zing detect`
Auto-detect project type and display information.

```bash
zing detect
```

**Output for Zig project:**
```
🔍 Detecting project type in: .
✅ Detected: Zig Project
   Name: hello-zig
   Version: 1.0.0
```

**Output for C project:**
```
🔍 Detecting project type in: .
✅ Detected: C Project
   Sources: 3 files
   Headers: 2 files
```

### `zing compile`
Compile native project using Zig compiler.

```bash
zing compile [--release]
```

**Options:**
- `--release` - Build in release mode (optimized)

**Examples:**
```bash
zing compile                           # Debug build
zing compile --release                 # Release build
```

### `zing cross`
Cross-compile for different target architectures.

```bash
zing cross <TARGET> [--release]
```

**Required:**
- `TARGET` - Target triple (e.g., x86_64-windows-gnu)

**Supported Targets:**
```bash
# Desktop platforms
x86_64-linux-gnu        # Linux x64 (glibc)
x86_64-linux-musl       # Linux x64 (musl)
x86_64-windows-gnu      # Windows x64
x86_64-macos            # macOS x64

# ARM platforms
aarch64-linux-gnu       # ARM64 Linux (glibc)
aarch64-linux-musl      # ARM64 Linux (musl)
aarch64-macos           # macOS ARM64 (M1/M2)
arm-linux-gnueabihf     # ARM32 Linux

# Other architectures
riscv64-linux-gnu       # RISC-V 64-bit
wasm32-wasi             # WebAssembly (WASI)
wasm32-freestanding     # WebAssembly (bare)
```

**Examples:**
```bash
zing cross x86_64-windows-gnu          # Windows executable
zing cross aarch64-linux-gnu --release # ARM64 Linux (optimized)
zing cross wasm32-wasi                 # WebAssembly
```

---

## Examples & Workflows

### Basic PKGBUILD Workflow
```bash
# Start new package
zing init

# Edit PKGBUILD file
vim PKGBUILD

# Test build
zing build

# Create final package
zing package

# Clean up
zing clean
```

### Cross-Compilation Workflow
```bash
# Detect project type
zing detect

# Build for current platform
zing compile --release

# Cross-compile for Windows
zing cross x86_64-windows-gnu --release
```
