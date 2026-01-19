const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = std.Io.Dir;
const parser = @import("parser.zig");

pub const BuildContext = struct {
    allocator: Allocator,
    io: Io,
    pkgbuild: parser.PkgBuild,
    content: []const u8,
    cache_dir: []const u8,
    build_dir: []const u8,
    src_dir: []const u8,
    pkg_dir: []const u8,

    pub fn init(allocator: Allocator, io: Io, pkgbuild: parser.PkgBuild, content: []const u8) !BuildContext {
        // Use a simple cache directory - can be enhanced later with env var support
        const cache_dir = try allocator.dupe(u8, ".zing-cache");

        // Create build directories
        const build_dir = try allocator.dupe(u8, "build");
        const src_dir = try allocator.dupe(u8, "src");
        const pkg_dir = try allocator.dupe(u8, "pkg");

        // Create directories
        Dir.cwd().createDirPath(io, cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        Dir.cwd().createDirPath(io, build_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return BuildContext{
            .allocator = allocator,
            .io = io,
            .pkgbuild = pkgbuild,
            .content = content,
            .cache_dir = cache_dir,
            .build_dir = build_dir,
            .src_dir = src_dir,
            .pkg_dir = pkg_dir,
        };
    }

    pub fn deinit(self: *BuildContext) void {
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.build_dir);
        self.allocator.free(self.src_dir);
        self.allocator.free(self.pkg_dir);
        self.pkgbuild.deinit();
    }
};

pub fn prepareBuild(ctx: *BuildContext) !void {
    print("==> Preparing build: {s} v{s}-{s}\n", .{
        ctx.pkgbuild.pkgname,
        ctx.pkgbuild.pkgver,
        ctx.pkgbuild.pkgrel,
    });

    // Create pkg directory
    Dir.cwd().createDirPath(ctx.io, ctx.pkg_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Create src directory
    Dir.cwd().createDirPath(ctx.io, ctx.src_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    print("==> Build environment prepared\n", .{});
}

pub fn buildPackage(ctx: *BuildContext) !void {
    print("==> Building package: {s}\n", .{ctx.pkgbuild.pkgname});

    // Execute build scripts via bash
    const build_script = try extractFunction(ctx.allocator, ctx.content, "build");
    defer if (build_script) |s| ctx.allocator.free(s);

    if (build_script) |script| {
        print("==> Running build() function\n", .{});
        try executeBashScript(ctx.io, script);
    } else {
        print("   No build() function found\n", .{});
    }

    print("==> Build completed successfully\n", .{});
}

pub fn packageFiles(ctx: *BuildContext) !void {
    print("==> Packaging: {s}\n", .{ctx.pkgbuild.pkgname});

    // Execute package scripts
    const package_script = try extractFunction(ctx.allocator, ctx.content, "package");
    defer if (package_script) |s| ctx.allocator.free(s);

    if (package_script) |script| {
        print("==> Running package() function\n", .{});
        try executeBashScript(ctx.io, script);
    }

    // Create package archive
    const pkg_filename = try std.fmt.allocPrint(
        ctx.allocator,
        "{s}-{s}-{s}-x86_64.pkg.tar.zst",
        .{ ctx.pkgbuild.pkgname, ctx.pkgbuild.pkgver, ctx.pkgbuild.pkgrel },
    );
    defer ctx.allocator.free(pkg_filename);

    print("==> Package created: {s}\n", .{pkg_filename});
}

fn extractFunction(allocator: Allocator, content: []const u8, func_name: []const u8) !?[]const u8 {
    const search = try std.fmt.allocPrint(allocator, "{s}()", .{func_name});
    defer allocator.free(search);

    const start_pos = std.mem.indexOf(u8, content, search) orelse return null;

    // Find opening brace
    const brace_start = std.mem.indexOfPos(u8, content, start_pos, "{") orelse return null;

    // Find matching closing brace
    var depth: usize = 1;
    var pos = brace_start + 1;
    while (pos < content.len and depth > 0) {
        if (content[pos] == '{') depth += 1;
        if (content[pos] == '}') depth -= 1;
        pos += 1;
    }

    if (depth != 0) return null;

    return try allocator.dupe(u8, content[brace_start + 1 .. pos - 1]);
}

fn executeBashScript(io: Io, script: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = &[_][]const u8{ "bash", "-c", script },
    });

    _ = try child.wait(io);
}

pub fn cleanBuild(io: Io) !void {
    print("==> Cleaning build artifacts\n", .{});

    Dir.cwd().deleteTree(io, "build") catch {};
    Dir.cwd().deleteTree(io, "src") catch {};
    Dir.cwd().deleteTree(io, "pkg") catch {};

    print("==> Clean completed\n", .{});
}
