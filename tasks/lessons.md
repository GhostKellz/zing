# Lessons

- When upgrading Zig versions, search for every `minimum_zig_version` and every hardcoded Zig version string before claiming the repo is aligned.
- Do not leave example projects on an older Zig version when the root project is being migrated to a newer toolchain.
- During doc and example cleanup, treat sample metadata files as part of the upgrade surface, not as secondary follow-up.
- Do not add CI workflows, automation, or repository-level process changes unless the user explicitly asks for them.
- When touching Zig std APIs, verify the exact 0.16 stdlib symbols and call patterns under `/opt/zig-0.16.0-dev/lib/std` before editing; do not infer old `std.time` or `std.posix` usage from memory.
