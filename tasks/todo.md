# Zing Next Steps

## Checklist

- [ ] Fix PKGBUILD source variable expansion in `src/builder.zig` so `source=("${pkgname}-${pkgver}.tar.gz")` and similar patterns resolve before copy/download.
- [ ] Fix archive extraction layout in `src/builder.zig` so extracted trees land under the paths real PKGBUILDs expect instead of adding an extra directory layer.
- [ ] Repair broken unit tests in `src/builder.zig` and `src/packager.zig` so direct file-level test runs pass without crashes or compile errors.
- [ ] Replace the ad-hoc dependency version comparison in `src/deps.zig` with Arch-compatible semantics, or degrade this preflight to warnings until it is accurate.
- [ ] Teach dependency preflight to account for pacman `provides` so virtual dependencies do not fail incorrectly.
- [ ] Tighten PKGBUILD parsing in `src/parser.zig` for common shell syntax the current split-on-space parser misreads.
- [ ] Fix the generated `zing init` PKGBUILD template so it is syntactically valid and matches what the parser/build path actually supports.
- [ ] Add regression tests for variable-expanded sources, renamed sources, extraction layout, dependency edge cases, and init-template validity.
- [ ] Re-run end-to-end verification with example PKGBUILDs and direct `zig test src/*.zig` coverage for the touched modules.
- [ ] Review docs again after code fixes so README and `docs/` describe only behavior that is actually verified.

## Review Notes

- Current baseline verification succeeded for `zig build`, `zig build test`, `./zig-out/bin/zing help`, and `./zig-out/bin/zing version`.
- Direct module testing is not healthy yet: `zig test src/packager.zig` currently fails to compile and `zig test src/builder.zig` currently aborts from a double free in test code.
- The highest-risk runtime issues are in PKGBUILD source handling and dependency preflight, because they can reject valid inputs or break common PKGBUILD layouts.
