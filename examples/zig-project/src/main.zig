const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    std.debug.print("Hello from Zig compiled with Zing!\n", .{});
    std.debug.print("Target: {s}-{s}\n", .{ @tagName(builtin.target.cpu.arch), @tagName(builtin.target.os.tag) });
    std.debug.print("Zig version: {}\n", .{builtin.zig_version});
}

test "simple test" {
    const testing = std.testing;
    try testing.expect(2 + 2 == 4);
}
