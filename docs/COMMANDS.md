# Zing Commands

## Usage

```bash
zing <command> [options]
```

## Commands

### `zing help`

Show the built-in help text.

### `zing version`

Show the current Zing version banner.

### `zing init`

Create an example `PKGBUILD` in the current directory if one does not already exist.

### `zing build [PKGBUILD]`

Parse the target PKGBUILD and run:

- `prepare()` if present
- `build()` if present
- `check()` if present
- dependency preflight for `depends` and `makedepends` when pacman is available

If no path is provided, Zing uses `./PKGBUILD`.

### `zing package [PKGBUILD]`

Run the build pipeline and then:

- execute `package()` if present
- create and verify a basic `.pkg.tar.zst` archive from `.zing-work/pkg/`

If no path is provided, Zing uses `./PKGBUILD`.

### `zing clean`

Remove `.zing-work/` and `.zing-cache/` from the current directory.

### `zing detect`

Detect whether the current directory looks like a Zig, C, C++, mixed, or unknown project.

### `zing compile [--release]`

Compile the current project:

- Zig projects use `zig build`
- C and C++ projects use `zig cc`

### `zing cross <target> [--release]`

Compile the current project for the given Zig target triple.

Examples:

```bash
zing cross x86_64-windows-gnu --release
zing cross aarch64-linux-gnu --release
zing cross wasm32-wasi
```

## Notes

- The current CLI does not expose cache reuse, AUR, multi-arch, or signing commands.
- The PKGBUILD path currently uses `.zing-work/` for transient build state and `.zing-cache/` for local cached sources.
