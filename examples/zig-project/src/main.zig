const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello from Zig compiled with zmake! 🚀\n");

    // Show some system info
    const target = @import("builtin").target;
    try stdout.print("Target: {s}-{s}\n", .{ @tagName(target.cpu.arch), @tagName(target.os.tag) });
    try stdout.print("Zig version: {}\n", .{@import("builtin").zig_version});
}

test "simple test" {
    const testing = std.testing;
    try testing.expect(2 + 2 == 4);
}
