//! Zing - Next-Generation Build & Packaging Engine for Arch Linux
//! This is the root library module exposing Zing's public API.

const std = @import("std");

pub const parser = @import("parser.zig");
pub const builder = @import("builder.zig");
pub const native = @import("native.zig");

pub const version = "0.1.0";
pub const name = "zing";

test "version is set" {
    try std.testing.expect(version.len > 0);
}
