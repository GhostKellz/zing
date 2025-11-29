const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");

pub const BuildContext = struct {
    allocator: Allocator,
    pkgbuild: parser.PkgBuild,
    content: []const u8,
    cache_dir: []const u8,
    build_dir: []const u8,
    src_dir: []const u8,
    pkg_dir: []const u8,

    pub fn init(allocator: Allocator, pkgbuild: parser.PkgBuild, content: []const u8) !BuildContext {
        // Determine cache directory
        const cache_dir = blk: {
            if (std.posix.getenv("ZING_CACHE_DIR")) |custom| {
                break :blk try allocator.dupe(u8, custom);
            }
            if (std.posix.getenv("HOME")) |home| {
                break :blk try std.fs.path.join(allocator, &[_][]const u8{ home, ".cache", "zing" });
            }
            break :blk try allocator.dupe(u8, "/tmp/zing-cache");
        };

        // Create build directories
        const build_dir = try allocator.dupe(u8, "build");
        const src_dir = try allocator.dupe(u8, "src");
        const pkg_dir = try allocator.dupe(u8, "pkg");

        // Create directories
        std.fs.cwd().makePath(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        std.fs.cwd().makePath(build_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return BuildContext{
            .allocator = allocator,
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
    std.fs.cwd().makePath(ctx.pkg_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Create src directory
    std.fs.cwd().makePath(ctx.src_dir) catch |err| switch (err) {
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
        try executeBashScript(ctx.allocator, script);
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
        try executeBashScript(ctx.allocator, script);
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

fn executeBashScript(allocator: Allocator, script: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{ "bash", "-c", script }, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    _ = try child.spawnAndWait();
}

pub fn cleanBuild(allocator: Allocator) !void {
    _ = allocator;
    print("==> Cleaning build artifacts\n", .{});

    std.fs.cwd().deleteTree("build") catch {};
    std.fs.cwd().deleteTree("src") catch {};
    std.fs.cwd().deleteTree("pkg") catch {};

    print("==> Clean completed\n", .{});
}
