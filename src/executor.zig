const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const parser = @import("parser.zig");

pub const ScriptResult = struct {
    success: bool,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,

    pub fn deinit(self: *ScriptResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub const BuildEnvironment = struct {
    srcdir: []const u8,
    pkgdir: []const u8,
    startdir: []const u8,
    pkgname: []const u8,
    pkgver: []const u8,
    pkgrel: []const u8,

    allocator: Allocator,

    pub fn init(allocator: Allocator, pkgbuild: *const parser.PkgBuild, build_root: []const u8) !BuildEnvironment {
        const srcdir = try std.fs.path.join(allocator, &[_][]const u8{ build_root, "src" });
        const pkgdir = try std.fs.path.join(allocator, &[_][]const u8{ build_root, "pkg" });
        const startdir = try allocator.dupe(u8, build_root);

        return BuildEnvironment{
            .srcdir = srcdir,
            .pkgdir = pkgdir,
            .startdir = startdir,
            .pkgname = try allocator.dupe(u8, pkgbuild.pkgname),
            .pkgver = try allocator.dupe(u8, pkgbuild.pkgver),
            .pkgrel = try allocator.dupe(u8, pkgbuild.pkgrel),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BuildEnvironment) void {
        self.allocator.free(self.srcdir);
        self.allocator.free(self.pkgdir);
        self.allocator.free(self.startdir);
        self.allocator.free(self.pkgname);
        self.allocator.free(self.pkgver);
        self.allocator.free(self.pkgrel);
    }

    pub fn getEnvMap(self: *const BuildEnvironment, allocator: Allocator) !std.process.EnvMap {
        var env_map = std.process.EnvMap.init(allocator);

        try env_map.put("srcdir", self.srcdir);
        try env_map.put("pkgdir", self.pkgdir);
        try env_map.put("startdir", self.startdir);
        try env_map.put("pkgname", self.pkgname);
        try env_map.put("pkgver", self.pkgver);
        try env_map.put("pkgrel", self.pkgrel);

        // Add some standard environment variables
        try env_map.put("CFLAGS", "-march=x86-64 -mtune=generic -O2 -pipe -fno-plt");
        try env_map.put("CXXFLAGS", "-march=x86-64 -mtune=generic -O2 -pipe -fno-plt");
        try env_map.put("LDFLAGS", "-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now");
        try env_map.put("MAKEFLAGS", "-j$(nproc)");

        return env_map;
    }
};

pub fn extractBashFunction(pkgbuild_content: []const u8, function_name: []const u8, allocator: Allocator) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, pkgbuild_content, '\n');
    var in_function = false;
    var brace_count: i32 = 0;
    var function_lines = ArrayList([]const u8).init(allocator);
    defer function_lines.deinit();

    const function_start = try std.fmt.allocPrint(allocator, "{s}()", .{function_name});
    defer allocator.free(function_start);

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (!in_function) {
            if (std.mem.startsWith(u8, trimmed, function_start)) {
                in_function = true;
                continue;
            }
        } else {
            // Count braces to know when function ends
            for (trimmed) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }

            if (brace_count < 0) break; // Function ended

            try function_lines.append(try allocator.dupe(u8, line));
        }
    }

    if (function_lines.items.len == 0) return null;

    // Join all lines
    const total_len = blk: {
        var len: usize = 0;
        for (function_lines.items) |line| {
            len += line.len + 1; // +1 for newline
        }
        break :blk len;
    };

    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (function_lines.items) |line| {
        @memcpy(result[pos .. pos + line.len], line);
        pos += line.len;
        result[pos] = '\n';
        pos += 1;
        allocator.free(line);
    }

    return result[0 .. pos - 1]; // Remove last newline
}

pub fn executeScript(allocator: Allocator, script: []const u8, env: *const BuildEnvironment, working_dir: []const u8) !ScriptResult {
    print("==> Executing script in: {s}\n", .{working_dir});

    // Create temporary script file
    const script_path = try std.fs.path.join(allocator, &[_][]const u8{ working_dir, "zmake_script.sh" });
    defer allocator.free(script_path);

    var script_file = try std.fs.cwd().createFile(script_path, .{ .mode = 0o755 });
    defer script_file.close();
    defer std.fs.cwd().deleteFile(script_path) catch {};

    // Write script with bash shebang and error handling
    try script_file.writeAll("#!/bin/bash\n");
    try script_file.writeAll("set -e\n"); // Exit on error
    try script_file.writeAll("set -u\n"); // Exit on undefined variable
    try script_file.writeAll(script);
    try script_file.writeAll("\n");

    // Prepare environment
    var env_map = try env.getEnvMap(allocator);
    defer env_map.deinit();

    // Execute script
    var child = std.process.Child.init(&[_][]const u8{ "/bin/bash", script_path }, allocator);
    child.cwd = working_dir;
    child.env_map = &env_map;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);

    const result = try child.wait();

    return ScriptResult{
        .success = result == .Exited and result.Exited == 0,
        .exit_code = if (result == .Exited) result.Exited else 1,
        .stdout = stdout,
        .stderr = stderr,
    };
}

pub fn executePkgBuildFunction(allocator: Allocator, pkgbuild_content: []const u8, function_name: []const u8, env: *const BuildEnvironment) !ScriptResult {
    const script = extractBashFunction(pkgbuild_content, function_name, allocator) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to extract {s}() function: {}", .{ function_name, err });
        defer allocator.free(error_msg);

        return ScriptResult{
            .success = false,
            .exit_code = 1,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try allocator.dupe(u8, error_msg),
        };
    };

    if (script == null) {
        print("==> No {s}() function found, skipping\n", .{function_name});
        return ScriptResult{
            .success = true,
            .exit_code = 0,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try allocator.dupe(u8, ""),
        };
    }

    defer allocator.free(script.?);

    const working_dir = if (std.mem.eql(u8, function_name, "package")) env.pkgdir else env.srcdir;

    const result = try executeScript(allocator, script.?, env, working_dir);

    if (!result.success) {
        print("❌ {s}() function failed with exit code: {d}\n", .{ function_name, result.exit_code });
        if (result.stderr.len > 0) {
            print("STDERR:\n{s}\n", .{result.stderr});
        }
    } else {
        print("✅ {s}() function completed successfully\n", .{function_name});
    }

    return result;
}
