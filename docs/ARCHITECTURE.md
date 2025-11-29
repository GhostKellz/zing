# 🏗️ Zing Architecture

This document describes the internal architecture and design of Zing.

---

## Overview

Zing is built using a modular architecture where each component handles a specific aspect of the build process:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CLI Parser    │───▶│  Build Context  │───▶│   Execution     │
│   (main.zig)    │    │  (builder.zig)  │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  Configuration  │    │  Native Builds  │
│  (parser.zig)   │    │  (native.zig)   │
└─────────────────┘    └─────────────────┘
```

---

## Core Components

### 1. CLI Parser (`main.zig`)

The main entry point that handles:
- Command-line argument parsing
- Command routing
- Help and version display
- Error handling and user feedback

```zig
const Command = enum {
    help,
    version,
    init,
    build,
    package,
    clean,
    detect,
    compile,
    cross_compile,
};
```

### 2. PKGBUILD Parser (`parser.zig`)

Parses traditional PKGBUILD files and extracts metadata:

```zig
pub const PkgBuild = struct {
    pkgname: []const u8,
    pkgver: []const u8,
    pkgrel: []const u8,
    pkgdesc: ?[]const u8,
    arch: [][]const u8,
    url: ?[]const u8,
    license: [][]const u8,
    depends: [][]const u8,
    makedepends: [][]const u8,
    source: [][]const u8,
    sha256sums: [][]const u8,
};
```

**Features:**
- Supports all standard PKGBUILD variables
- Handles bash arrays and string escaping
- Validates required fields
- Memory-safe parsing with proper cleanup

### 3. Build Orchestrator (`builder.zig`)

Coordinates the entire build process:

```zig
pub const BuildContext = struct {
    allocator: Allocator,
    pkgbuild: parser.PkgBuild,
    cache_dir: []const u8,
    build_dir: []const u8,
    src_dir: []const u8,
    pkg_dir: []const u8,
};
```

**Build Pipeline:**
1. **Preparation** - Create build directories
2. **Script Extraction** - Parse PKGBUILD functions
3. **Execution** - Run build/package functions via bash
4. **Packaging** - Create final package archive

### 4. Native Project Compiler (`native.zig`)

Handles native Zig/C/C++ project compilation:

```zig
pub const ProjectType = enum {
    zig,
    c,
    cpp,
    mixed,
    unknown,
};
```

**Features:**
- Auto-detection of project types
- Zig compiler integration
- Cross-compilation support
- Build metadata extraction from build.zig.zon

---

## Data Flow

### PKGBUILD Build Flow

```
1. User runs: zing build
           │
           ▼
2. main.zig parses command
           │
           ▼
3. parser.zig reads PKGBUILD
           │
           ▼
4. builder.zig creates BuildContext
           │
           ▼
5. Extract build() function
           │
           ▼
6. Execute via bash subprocess
           │
           ▼
7. Create package archive
```

### Native Compilation Flow

```
1. User runs: zing compile
           │
           ▼
2. native.zig detects project type
           │
           ▼
3. Analyze project (sources, version)
           │
           ▼
4. Invoke zig build / zig cc
           │
           ▼
5. Report success/failure
```

---

## Memory Management

Zing uses Zig's allocator pattern throughout:

- **GeneralPurposeAllocator** for main program
- **ArenaAllocator** for temporary allocations
- Explicit `deinit()` calls for cleanup
- `errdefer` for error-path cleanup

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

---

## Error Handling

All functions use Zig's error union pattern:

```zig
pub fn parsePkgBuild(allocator: Allocator, content: []const u8) !PkgBuild {
    // Returns error or value
}
```

Errors are propagated up with meaningful context and displayed to the user.

---

## Future Architecture

Planned additions:

- **Cache System** - Content-addressable build cache
- **Dependency Resolver** - Pacman database integration
- **Parallel Downloader** - HTTP client for sources
- **Package Archiver** - tar.zst creation
- **AUR Client** - RPC API integration
