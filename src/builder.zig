const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = std.Io.Dir;
const parser = @import("parser.zig");
const packager = @import("packager.zig");
const deps = @import("deps.zig");

pub const BuildContext = struct {
    allocator: Allocator,
    io: Io,
    pkgbuild: parser.PkgBuild,
    content: []const u8,
    pkgbuild_dir: []const u8,
    work_dir: []const u8,
    cache_dir: []const u8,
    build_dir: []const u8,
    src_dir: []const u8,
    pkg_dir: []const u8,

    pub fn init(allocator: Allocator, io: Io, pkgbuild: parser.PkgBuild, content: []const u8, pkgbuild_path: []const u8) !BuildContext {
        const pkgbuild_dir_raw = Dir.path.dirname(pkgbuild_path) orelse ".";
        const cwd = try std.process.currentPathAlloc(io, allocator);
        defer allocator.free(cwd);

        const pkgbuild_dir = if (std.fs.path.isAbsolute(pkgbuild_dir_raw))
            try allocator.dupe(u8, pkgbuild_dir_raw)
        else
            try Dir.path.join(allocator, &.{ cwd, pkgbuild_dir_raw });

        const work_dir = try Dir.path.join(allocator, &.{ pkgbuild_dir, ".zing-work" });

        // Use a simple cache directory - can be enhanced later with env var support
        const cache_dir = try Dir.path.join(allocator, &.{ pkgbuild_dir, ".zing-cache" });

        // Create build directories
        const build_dir = try Dir.path.join(allocator, &.{ work_dir, "build" });
        const src_dir = try Dir.path.join(allocator, &.{ work_dir, "src" });
        const pkg_dir = try Dir.path.join(allocator, &.{ work_dir, "pkg" });

        // Create directories
        Dir.cwd().createDirPath(io, work_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
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
            .pkgbuild_dir = pkgbuild_dir,
            .work_dir = work_dir,
            .cache_dir = cache_dir,
            .build_dir = build_dir,
            .src_dir = src_dir,
            .pkg_dir = pkg_dir,
        };
    }

    pub fn deinit(self: *BuildContext) void {
        self.allocator.free(self.pkgbuild_dir);
        self.allocator.free(self.work_dir);
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

    try checkDependencies(ctx);
    try materializeSources(ctx);

    print("==> Build environment prepared\n", .{});
}

pub fn buildPackage(ctx: *BuildContext) !void {
    print("==> Building package: {s}\n", .{ctx.pkgbuild.pkgname});

    const prepare_script = try extractFunction(ctx.allocator, ctx.content, "prepare");
    defer if (prepare_script) |s| ctx.allocator.free(s);

    if (prepare_script) |script| {
        print("==> Running prepare() function\n", .{});
        try executeBashScript(ctx.io, script, ctx.src_dir, ctx.pkgbuild_dir, ctx.build_dir, ctx.src_dir, ctx.pkg_dir, ctx.pkgbuild.pkgname, ctx.pkgbuild.pkgver, ctx.pkgbuild.pkgrel);
    }

    const build_script = try extractFunction(ctx.allocator, ctx.content, "build");
    defer if (build_script) |s| ctx.allocator.free(s);

    if (build_script) |script| {
        print("==> Running build() function\n", .{});
        try executeBashScript(ctx.io, script, ctx.src_dir, ctx.pkgbuild_dir, ctx.build_dir, ctx.src_dir, ctx.pkg_dir, ctx.pkgbuild.pkgname, ctx.pkgbuild.pkgver, ctx.pkgbuild.pkgrel);
    } else {
        print("   No build() function found\n", .{});
    }

    const check_script = try extractFunction(ctx.allocator, ctx.content, "check");
    defer if (check_script) |s| ctx.allocator.free(s);

    if (check_script) |script| {
        print("==> Running check() function\n", .{});
        try executeBashScript(ctx.io, script, ctx.src_dir, ctx.pkgbuild_dir, ctx.build_dir, ctx.src_dir, ctx.pkg_dir, ctx.pkgbuild.pkgname, ctx.pkgbuild.pkgver, ctx.pkgbuild.pkgrel);
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
        try executeBashScript(ctx.io, script, ctx.src_dir, ctx.pkgbuild_dir, ctx.build_dir, ctx.src_dir, ctx.pkg_dir, ctx.pkgbuild.pkgname, ctx.pkgbuild.pkgver, ctx.pkgbuild.pkgrel);
    }

    // Create package archive
    const pkg_filename = try std.fmt.allocPrint(
        ctx.allocator,
        "{s}-{s}-{s}-{s}.pkg.tar.zst",
        .{ ctx.pkgbuild.pkgname, ctx.pkgbuild.pkgver, ctx.pkgbuild.pkgrel, packageArch(&ctx.pkgbuild) },
    );
    defer ctx.allocator.free(pkg_filename);

    const output_path = try Dir.path.join(ctx.allocator, &.{ ctx.pkgbuild_dir, pkg_filename });
    defer ctx.allocator.free(output_path);

    var archiver = packager.PackageArchiver.init(ctx.allocator);
    try archiver.createPackage(ctx.io, &ctx.pkgbuild, ctx.pkg_dir, output_path);
    const verified = try archiver.verifyPackage(ctx.io, output_path);
    if (!verified) return error.PackageVerificationFailed;

    print("==> Package created: {s}\n", .{output_path});
}

fn packageArch(pkgbuild: *const parser.PkgBuild) []const u8 {
    return if (pkgbuild.arch.len > 0) pkgbuild.arch[0] else "any";
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

const SourceSpec = struct {
    name: []const u8,
    location: []const u8,
    is_url: bool,
};

fn isSupportedRemoteSource(location: []const u8) bool {
    return std.mem.startsWith(u8, location, "http://") or std.mem.startsWith(u8, location, "https://");
}

fn isUnsupportedSource(location: []const u8) bool {
    return std.mem.startsWith(u8, location, "git+") or
        std.mem.startsWith(u8, location, "hg+") or
        std.mem.startsWith(u8, location, "svn+") or
        std.mem.startsWith(u8, location, "bzr+") or
        (std.mem.indexOf(u8, location, "://") != null and !isSupportedRemoteSource(location));
}

const StagedSource = struct {
    path: []const u8,
    extracted_dir: ?[]const u8,

    fn deinit(self: StagedSource, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.extracted_dir) |dir| allocator.free(dir);
    }
};

fn parseSourceSpec(source: []const u8) SourceSpec {
    var name = Dir.path.basename(source);
    var location = source;

    if (std.mem.indexOf(u8, source, "::")) |sep| {
        name = source[0..sep];
        location = source[sep + 2 ..];
    }

    const is_url = std.mem.indexOf(u8, location, "://") != null;
    if (is_url and std.mem.indexOf(u8, source, "::") == null) {
        name = Dir.path.basename(location);
    }

    return .{
        .name = name,
        .location = location,
        .is_url = is_url,
    };
}

fn copyFile(ctx: *BuildContext, source_path: []const u8, dest_path: []const u8) !void {
    var src = try Dir.cwd().openFile(ctx.io, source_path, .{});
    defer src.close(ctx.io);

    var dest = try Dir.cwd().createFile(ctx.io, dest_path, .{});
    defer dest.close(ctx.io);

    var read_buffer: [4096]u8 = undefined;
    var reader = std.Io.File.Reader.init(src, ctx.io, &read_buffer);
    var chunk: [4096]u8 = undefined;

    while (true) {
        const bytes_read = try reader.interface.readSliceShort(&chunk);
        if (bytes_read == 0) break;
        try dest.writeStreamingAll(ctx.io, chunk[0..bytes_read]);
    }
}

fn verifySha256(ctx: *BuildContext, file_path: []const u8, expected_hash: []const u8) !void {
    if (std.mem.eql(u8, expected_hash, "SKIP")) return;

    var file = try Dir.cwd().openFile(ctx.io, file_path, .{});
    defer file.close(ctx.io);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var read_buffer: [8192]u8 = undefined;
    var reader = std.Io.File.Reader.init(file, ctx.io, &read_buffer);
    var chunk: [8192]u8 = undefined;

    while (true) {
        const bytes_read = try reader.interface.readSliceShort(&chunk);
        if (bytes_read == 0) break;
        hasher.update(chunk[0..bytes_read]);
    }

    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);

    var hash_hex: [64]u8 = undefined;
    const actual_hash = try std.fmt.bufPrint(&hash_hex, "{x}", .{hash_bytes});
    if (!std.ascii.eqlIgnoreCase(actual_hash, expected_hash)) {
        return error.ChecksumMismatch;
    }
}

fn isArchiveFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".tar") or
        std.mem.endsWith(u8, path, ".tar.gz") or
        std.mem.endsWith(u8, path, ".tgz") or
        std.mem.endsWith(u8, path, ".tar.xz") or
        std.mem.endsWith(u8, path, ".tar.zst") or
        std.mem.endsWith(u8, path, ".zip");
}

fn archiveExtractDir(allocator: Allocator, archive_path: []const u8) ![]const u8 {
    var base = Dir.path.basename(archive_path);

    const suffixes = [_][]const u8{ ".tar.gz", ".tar.xz", ".tar.zst", ".tgz", ".tar", ".zip" };
    for (suffixes) |suffix| {
        if (std.mem.endsWith(u8, base, suffix)) {
            base = base[0 .. base.len - suffix.len];
            break;
        }
    }

    return try allocator.dupe(u8, base);
}

fn appendExpandedVariable(allocator: Allocator, output: *std.ArrayListUnmanaged(u8), pkgbuild: *const parser.PkgBuild, variable: []const u8) !bool {
    const value = if (std.mem.eql(u8, variable, "pkgname"))
        pkgbuild.pkgname
    else if (std.mem.eql(u8, variable, "pkgver"))
        pkgbuild.pkgver
    else if (std.mem.eql(u8, variable, "pkgrel"))
        pkgbuild.pkgrel
    else
        return false;

    try output.appendSlice(allocator, value);
    return true;
}

fn expandPkgBuildVariables(allocator: Allocator, pkgbuild: *const parser.PkgBuild, input: []const u8) ![]const u8 {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(allocator);

    var i: usize = 0;
    scan: while (i < input.len) {
        if (input[i] != '$') {
            try output.append(allocator, input[i]);
            i += 1;
            continue;
        }

        if (i + 1 >= input.len) {
            try output.append(allocator, input[i]);
            break;
        }

        if (input[i + 1] == '{') {
            const end = std.mem.indexOfScalarPos(u8, input, i + 2, '}');
            if (end) |close| {
                if (try appendExpandedVariable(allocator, &output, pkgbuild, input[i + 2 .. close])) {
                    i = close + 1;
                    continue;
                }
            }
        } else {
            const variable_names = [_][]const u8{ "pkgname", "pkgver", "pkgrel" };
            for (variable_names) |name| {
                if (std.mem.startsWith(u8, input[i + 1 ..], name)) {
                    _ = try appendExpandedVariable(allocator, &output, pkgbuild, name);
                    i += 1 + name.len;
                    continue :scan;
                }
            }
        }

        try output.append(allocator, input[i]);
        i += 1;
    }

    return try output.toOwnedSlice(allocator);
}

fn extractArchive(ctx: *BuildContext, archive_path: []const u8) ![]const u8 {
    const extract_dir_name = try archiveExtractDir(ctx.allocator, archive_path);
    defer ctx.allocator.free(extract_dir_name);

    const extract_dir = try Dir.path.join(ctx.allocator, &.{ ctx.src_dir, extract_dir_name });
    errdefer ctx.allocator.free(extract_dir);

    const argv = if (std.mem.endsWith(u8, archive_path, ".zip"))
        &[_][]const u8{ "unzip", "-o", archive_path, "-d", ctx.src_dir }
    else if (std.mem.endsWith(u8, archive_path, ".tar.zst"))
        &[_][]const u8{ "tar", "--use-compress-program=zstd", "-xf", archive_path, "-C", ctx.src_dir }
    else
        &[_][]const u8{ "tar", "-xf", archive_path, "-C", ctx.src_dir };

    var child = try std.process.spawn(ctx.io, .{ .argv = argv });
    const result = try child.wait(ctx.io);
    switch (result) {
        .exited => |code| if (code != 0) return error.SourceExtractionFailed,
        else => return error.SourceExtractionFailed,
    }

    return extract_dir;
}

fn stageSource(ctx: *BuildContext, source: []const u8, expected_hash: ?[]const u8) !StagedSource {
    const expanded_source = try expandPkgBuildVariables(ctx.allocator, &ctx.pkgbuild, source);
    defer ctx.allocator.free(expanded_source);

    const spec = parseSourceSpec(expanded_source);

    if (isUnsupportedSource(spec.location)) {
        print("❌ Unsupported source format: {s}\n", .{spec.location});
        return error.UnsupportedSourceFormat;
    }

    const dest_path = try Dir.path.join(ctx.allocator, &.{ ctx.src_dir, spec.name });
    errdefer ctx.allocator.free(dest_path);

    if (spec.is_url) {
        print("==> Downloading source: {s}\n", .{spec.location});
        try downloadSource(ctx, spec.location, dest_path);
    } else {
        const source_path = if (std.fs.path.isAbsolute(spec.location))
            try ctx.allocator.dupe(u8, spec.location)
        else
            try Dir.path.join(ctx.allocator, &.{ ctx.pkgbuild_dir, spec.location });
        defer ctx.allocator.free(source_path);

        print("==> Copying source: {s}\n", .{spec.location});
        try copyFile(ctx, source_path, dest_path);
    }

    if (expected_hash) |hash| {
        try verifySha256(ctx, dest_path, hash);
    }

    const extracted_dir = if (isArchiveFile(dest_path)) try extractArchive(ctx, dest_path) else null;
    return .{ .path = dest_path, .extracted_dir = extracted_dir };
}

fn downloadSource(ctx: *BuildContext, url: []const u8, dest_path: []const u8) !void {
    var child = try std.process.spawn(ctx.io, .{
        .argv = &.{ "curl", "-fsSL", "-o", dest_path, url },
    });

    const result = try child.wait(ctx.io);
    switch (result) {
        .exited => |code| if (code != 0) return error.SourceDownloadFailed,
        else => return error.SourceDownloadFailed,
    }
}

fn materializeSources(ctx: *BuildContext) !void {
    if (ctx.pkgbuild.sha256sums.len != 0 and ctx.pkgbuild.sha256sums.len != ctx.pkgbuild.source.len) {
        return error.InvalidChecksumCount;
    }

    for (ctx.pkgbuild.source, 0..) |source, i| {
        const expected_hash = if (ctx.pkgbuild.sha256sums.len == ctx.pkgbuild.source.len) ctx.pkgbuild.sha256sums[i] else null;
        const staged = try stageSource(ctx, source, expected_hash);
        staged.deinit(ctx.allocator);
    }
}

fn checkDependencies(ctx: *BuildContext) !void {
    var required: std.ArrayListUnmanaged([]const u8) = .empty;
    defer required.deinit(ctx.allocator);

    try required.appendSlice(ctx.allocator, ctx.pkgbuild.depends);
    try required.appendSlice(ctx.allocator, ctx.pkgbuild.makedepends);

    if (required.items.len == 0) return;

    var resolver = try deps.DependencyResolver.init(ctx.allocator, ctx.io);
    defer resolver.deinit();

    const missing = try resolver.checkDependencies(required.items);
    defer {
        for (missing) |*dep| dep.deinit(ctx.allocator);
        ctx.allocator.free(missing);
    }

    if (missing.len == 0) return;

    print("\n==> Missing dependencies:\n", .{});
    for (missing) |dep| {
        print("    {s}\n", .{dep.name});
    }

    try resolver.suggestAURPackages(missing);
    return error.MissingDependencies;
}

fn executeBashScript(io: Io, script: []const u8, cwd: []const u8, start_dir: []const u8, build_dir: []const u8, src_dir: []const u8, pkg_dir: []const u8, pkgname: []const u8, pkgver: []const u8, pkgrel: []const u8) !void {
    const script_with_env = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "set -eu\nstartdir=\"{s}\"\nbuilddir=\"{s}\"\nsrcdir=\"{s}\"\npkgdir=\"{s}\"\npkgname=\"{s}\"\npkgver=\"{s}\"\npkgrel=\"{s}\"\nexport startdir builddir srcdir pkgdir pkgname pkgver pkgrel\n{s}",
        .{ start_dir, build_dir, src_dir, pkg_dir, pkgname, pkgver, pkgrel, script },
    );
    defer std.heap.page_allocator.free(script_with_env);

    var child = try std.process.spawn(io, .{
        .argv = &[_][]const u8{ "bash", "-c", script_with_env },
        .cwd = .{ .path = cwd },
    });

    const result = try child.wait(io);
    switch (result) {
        .exited => |code| if (code != 0) return error.ScriptFailed,
        else => return error.ScriptFailed,
    }
}

pub fn cleanBuild(io: Io) !void {
    print("==> Cleaning build artifacts\n", .{});

    Dir.cwd().deleteTree(io, ".zing-work") catch {};
    Dir.cwd().deleteTree(io, ".zing-cache") catch {};

    print("==> Clean completed\n", .{});
}

test "extractFunction returns function body" {
    const allocator = std.testing.allocator;
    const content =
        \\prepare() {
        \\    echo prepare
        \\}
        \\
        \\build() {
        \\    echo build
        \\    if true; then
        \\        echo nested
        \\    fi
        \\}
    ;

    const script = try extractFunction(allocator, content, "build");
    defer allocator.free(script.?);

    try std.testing.expect(script != null);
    try std.testing.expect(std.mem.indexOf(u8, script.?, "echo build") != null);
    try std.testing.expect(std.mem.indexOf(u8, script.?, "echo nested") != null);
}

test "extractFunction returns null for missing function" {
    const allocator = std.testing.allocator;
    const script = try extractFunction(allocator, "pkgname=demo\n", "package");
    try std.testing.expect(script == null);
}

test "parseSourceSpec handles renamed url" {
    const spec = parseSourceSpec("hello.c::https://example.invalid/hello.c");
    try std.testing.expectEqualStrings("hello.c", spec.name);
    try std.testing.expectEqualStrings("https://example.invalid/hello.c", spec.location);
    try std.testing.expect(spec.is_url);
}

test "stageSource rejects unsupported vcs sources" {
    try std.testing.expectError(error.UnsupportedSourceFormat, blk: {
        const pkgbuild = try parser.parsePkgBuild(std.testing.allocator,
            \\pkgname=demo
            \\pkgver=1.0.0
            \\pkgrel=1
            \\arch=('x86_64')
        );

        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        const pkgbuild_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "PKGBUILD" });
        defer std.testing.allocator.free(pkgbuild_path);

        var ctx = try BuildContext.init(std.testing.allocator, std.testing.io, pkgbuild, "", pkgbuild_path);
        defer ctx.deinit();

        break :blk stageSource(&ctx, "git+https://example.invalid/demo.git", null);
    });
}

test "expandPkgBuildVariables resolves pkg metadata tokens" {
    var pkgbuild = try parser.parsePkgBuild(std.testing.allocator,
        \\pkgname=demo
        \\pkgver=1.2.3
        \\pkgrel=4
        \\arch=('x86_64')
    );
    defer pkgbuild.deinit();

    const expanded = try expandPkgBuildVariables(std.testing.allocator, &pkgbuild, "${pkgname}-${pkgver}-${pkgrel}.tar.gz");
    defer std.testing.allocator.free(expanded);

    try std.testing.expectEqualStrings("demo-1.2.3-4.tar.gz", expanded);
}

test "stageSource expands pkgbuild variables for local files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "demo-1.2.3");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "demo-1.2.3/README", .data = "archive\n" });

    const pkgbuild = try parser.parsePkgBuild(std.testing.allocator,
        \\pkgname=demo
        \\pkgver=1.2.3
        \\pkgrel=1
        \\arch=('x86_64')
    );

    const pkgbuild_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "PKGBUILD" });
    defer std.testing.allocator.free(pkgbuild_path);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(root_path);
    const archive_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "demo-1.2.3.tar.gz" });
    defer std.testing.allocator.free(archive_path);

    var ctx = try BuildContext.init(std.testing.allocator, std.testing.io, pkgbuild, "", pkgbuild_path);
    defer ctx.deinit();

    try Dir.cwd().createDirPath(std.testing.io, ctx.src_dir);

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ "tar", "-czf", archive_path, "-C", root_path, "demo-1.2.3" },
    });
    const tar_result = try child.wait(std.testing.io);
    try std.testing.expect(tar_result == .exited and tar_result.exited == 0);

    const staged = try stageSource(&ctx, "${pkgname}-${pkgver}.tar.gz", null);
    defer staged.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("demo-1.2.3.tar.gz", std.fs.path.basename(staged.path));
}

test "verifySha256 detects mismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "demo.txt", .data = "hello\n" });

    const pkgbuild = try parser.parsePkgBuild(std.testing.allocator,
        \\pkgname=demo
        \\pkgver=1.0.0
        \\pkgrel=1
        \\arch=('x86_64')
    );

    const pkgbuild_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "PKGBUILD" });
    defer std.testing.allocator.free(pkgbuild_path);

    var ctx = try BuildContext.init(std.testing.allocator, std.testing.io, pkgbuild, "", pkgbuild_path);
    defer ctx.deinit();

    const file_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "demo.txt" });
    defer std.testing.allocator.free(file_path);

    try std.testing.expectError(error.ChecksumMismatch, verifySha256(&ctx, file_path, "0000000000000000000000000000000000000000000000000000000000000000"));
}

test "isArchiveFile detects common archive extensions" {
    try std.testing.expect(isArchiveFile("demo.tar.gz"));
    try std.testing.expect(isArchiveFile("demo.tgz"));
    try std.testing.expect(isArchiveFile("demo.tar.xz"));
    try std.testing.expect(isArchiveFile("demo.tar.zst"));
    try std.testing.expect(isArchiveFile("demo.zip"));
    try std.testing.expect(!isArchiveFile("demo.c"));
}

test "archiveExtractDir strips archive suffixes" {
    const allocator = std.testing.allocator;
    const a = try archiveExtractDir(allocator, "/tmp/demo.tar.gz");
    defer allocator.free(a);
    try std.testing.expectEqualStrings("demo", a);

    const b = try archiveExtractDir(allocator, "demo.zip");
    defer allocator.free(b);
    try std.testing.expectEqualStrings("demo", b);
}

test "extractArchive unpacks into srcdir without extra nesting" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "demo-1.0.0");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "demo-1.0.0/hello.txt", .data = "hello\n" });

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(root_path);

    const archive_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "demo-1.0.0.tar.gz" });
    defer std.testing.allocator.free(archive_path);

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ "tar", "-czf", archive_path, "-C", root_path, "demo-1.0.0" },
    });
    const tar_result = try child.wait(std.testing.io);
    try std.testing.expect(tar_result == .exited and tar_result.exited == 0);

    const pkgbuild = try parser.parsePkgBuild(std.testing.allocator,
        \\pkgname=demo
        \\pkgver=1.0.0
        \\pkgrel=1
        \\arch=('x86_64')
    );

    const pkgbuild_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "PKGBUILD" });
    defer std.testing.allocator.free(pkgbuild_path);

    var ctx = try BuildContext.init(std.testing.allocator, std.testing.io, pkgbuild, "", pkgbuild_path);
    defer ctx.deinit();

    try Dir.cwd().createDirPath(std.testing.io, ctx.src_dir);

    const extracted_dir = try extractArchive(&ctx, archive_path);
    defer std.testing.allocator.free(extracted_dir);

    const expected_root = try std.fs.path.join(std.testing.allocator, &.{ ctx.src_dir, "demo-1.0.0" });
    defer std.testing.allocator.free(expected_root);
    const nested_root = try std.fs.path.join(std.testing.allocator, &.{ extracted_dir, "demo-1.0.0" });
    defer std.testing.allocator.free(nested_root);

    const extracted_file = try std.fs.path.join(std.testing.allocator, &.{ expected_root, "hello.txt" });
    defer std.testing.allocator.free(extracted_file);
    const nested_file = try std.fs.path.join(std.testing.allocator, &.{ nested_root, "hello.txt" });
    defer std.testing.allocator.free(nested_file);

    _ = try Dir.cwd().statFile(std.testing.io, extracted_file, .{});
    try std.testing.expectError(error.FileNotFound, Dir.cwd().statFile(std.testing.io, nested_file, .{}));
}
