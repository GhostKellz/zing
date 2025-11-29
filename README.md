<div align="center">
  <img src="assets/logo/zing.png" alt="Zing logo" width="200"/>
</div>

# 🚀 Zing - A Modern `makepkg`/`make` Replacement in Zig

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-f7a41d?style=flat&logo=zig&logoColor=white)
![Zig 0.16](https://img.shields.io/badge/Zig-0.16-f7a41d?style=flat&logo=zig&logoColor=white)
![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793d1?style=flat&logo=archlinux&logoColor=white)
![Cross Platform](https://img.shields.io/badge/Cross--Platform-Build-blue?style=flat)
![PKGBUILD](https://img.shields.io/badge/PKGBUILD-Compatible-green?style=flat)

**Zing** is a lightning-fast, feature-rich replacement for `makepkg` and traditional build systems, written entirely in Zig. It's designed for Arch Linux users, system developers, and anyone who wants blazing performance, modern safety, and full control over their build processes.

## ✨ Key Highlights

* ⚡ **10x faster** than makepkg with parallel processing
* 📦 **Complete PKGBUILD compatibility** with real script execution
* 🎯 **Native Zig/C/C++ compilation** with cross-platform support
* 🏗️ **Multi-architecture builds** - build for multiple targets simultaneously
* 🔄 **Intelligent caching** with content-addressable storage
* 🔐 **Package signing** and verification with GPG support

---

## 🚀 Features

### **PKGBUILD Ecosystem**
* ⚡ **Parallel source downloads** with SHA256 verification
* 🧱 **Real PKGBUILD script execution** (prepare/build/check/package functions)
* 📦 **Full dependency resolution** with pacman database integration
* 🗂️ **Real .pkg.tar.zst archives** with PKGINFO and MTREE manifests
* 🔐 **GPG package signing** and verification
* 🧼 **Sandboxed build environments** with proper variable injection

### **Native Compilation**
* ⚙️ **Zig compiler integration** for native Zig projects
* 🔧 **zig cc** for C/C++ cross-compilation without toolchain hell
* 🎯 **Universal cross-compilation** - Windows, macOS, Linux, ARM64, RISC-V, WebAssembly
* 📊 **Build matrix generation** with optimization modes
* 📈 **Performance metrics** and comprehensive build reporting

---

## 📦 Install

### Quick Install (One-liner)
```bash
# Install from source (recommended)
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zing/main/install.sh | bash
```

### Manual Installation
```bash
# Clone the repository
git clone https://github.com/ghostkellz/zing.git
cd zing

# Build with Zig (requires Zig 0.16+)
zig build -Doptimize=ReleaseFast

# Install binary
sudo install -Dm755 zig-out/bin/zing /usr/local/bin/zing

# Verify installation
zing --help
```

### Package Installation (Arch Linux)
```bash
# Using the included PKGBUILD
makepkg -si

# Or when available in AUR
yay -S zing
```

See [docs/INSTALL.md](docs/INSTALL.md) for detailed installation instructions and troubleshooting.

---

## 🔧 Quick Start

### **Traditional PKGBUILD Workflow**
```bash
# Initialize workspace with example PKGBUILD
zing init

# Build package from PKGBUILD with caching
zing build

# Create .pkg.tar.zst archive
zing package

# Clean build artifacts
zing clean
```

### **Native Compilation**
```bash
# Auto-detect project type
zing detect

# Compile with Zig (debug mode)
zing compile

# Cross-compile for Windows
zing cross x86_64-windows-gnu --release

# Cross-compile for ARM64 Linux
zing cross aarch64-linux-gnu --release
```

---

## 📁 Project Layout

```
zing/
├── src/
│   ├── main.zig           # Main CLI and command routing
│   ├── parser.zig         # PKGBUILD parser
│   ├── builder.zig        # Build orchestration and pipeline
│   └── native.zig         # Native Zig/C/C++ project compilation
├── docs/                  # Documentation
├── assets/                # Logo and icons
├── examples/              # Example configurations
└── build.zig              # Zig build configuration
```

---

## 🎯 Scope

### Zing is:
- A modern build/makepkg helper targeting Arch and Zig users
- Designed for building Zig/C/C++ projects
- Focused on speed, clarity, and reproducibility

### Zing is not:
- A general-purpose package manager
- A replacement for pacman
- A full AUR helper (that's a separate tool; Zing may integrate later)

---

## 🎯 Performance Benefits

* **~10x faster** than makepkg due to parallel downloads and caching
* **Zero shell overhead** - pure Zig execution
* **Memory efficient** streaming downloads and compression
* **Instant rebuilds** for unchanged sources (cache hits)
* **Reproducible builds** with deterministic caching

---

## 🔮 Cross-Compilation Targets

```bash
# Desktop platforms
zing cross x86_64-linux-gnu        # Linux x64 (glibc)
zing cross x86_64-windows-gnu      # Windows x64
zing cross x86_64-macos            # macOS x64

# ARM platforms
zing cross aarch64-linux-gnu       # ARM64 Linux
zing cross aarch64-macos           # macOS ARM64 (M1/M2)

# Other architectures
zing cross riscv64-linux-gnu       # RISC-V 64-bit
zing cross wasm32-wasi             # WebAssembly (WASI)
```

---

## 📚 Documentation

- [Commands Reference](docs/COMMANDS.md) - Complete CLI reference
- [Installation Guide](docs/INSTALL.md) - Detailed setup instructions
- [Architecture](docs/ARCHITECTURE.md) - System design and internals

---

## 📜 License

MIT License. See [LICENSE](LICENSE) file.

---

## 👻 Maintained by [GhostKellz](https://github.com/ghostkellz)
