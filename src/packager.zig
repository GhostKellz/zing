const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const Dir = std.Io.Dir;
const parser = @import("parser.zig");

pub const PackageInfo = struct {
    pkgname: []const u8,
    pkgver: []const u8,
    pkgrel: []const u8,
    pkgdesc: ?[]const u8,
    url: ?[]const u8,
    builddate: i64,
    packager: []const u8,
    size: u64,
    arch: []const u8,
    license: [][]const u8,
    depends: [][]const u8,

    pub fn generatePkgInfo(self: *const PackageInfo, allocator: Allocator) ![]const u8 {
        var content: ArrayList(u8) = .empty;
        defer content.deinit(allocator);

        try content.print(allocator, "pkgname = {s}\n", .{self.pkgname});
        try content.print(allocator, "pkgver = {s}\n", .{self.pkgver});
        try content.print(allocator, "pkgrel = {s}\n", .{self.pkgrel});

        if (self.pkgdesc) |desc| {
            try content.print(allocator, "pkgdesc = {s}\n", .{desc});
        }

        if (self.url) |u| {
            try content.print(allocator, "url = {s}\n", .{u});
        }

        try content.print(allocator, "builddate = {d}\n", .{self.builddate});
        try content.print(allocator, "packager = {s}\n", .{self.packager});
        try content.print(allocator, "size = {d}\n", .{self.size});
        try content.print(allocator, "arch = {s}\n", .{self.arch});

        for (self.license) |lic| {
            try content.print(allocator, "license = {s}\n", .{lic});
        }

        for (self.depends) |dep| {
            try content.print(allocator, "depend = {s}\n", .{dep});
        }

        return try content.toOwnedSlice(allocator);
    }
};

pub const FileEntry = struct {
    path: []const u8,
    mode: u32,
    size: u64,
    checksum: []const u8,

    pub fn deinit(self: *FileEntry, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.checksum);
    }
};

pub const PackageArchiver = struct {
    allocator: Allocator,
    compression_level: u8,

    pub fn init(allocator: Allocator) PackageArchiver {
        return PackageArchiver{
            .allocator = allocator,
            .compression_level = 3, // Default zstd compression level
        };
    }

    fn readFileAlloc(self: *PackageArchiver, io: Io, file: std.Io.File, max_size: usize) ![]u8 {
        var result: ArrayList(u8) = .empty;
        defer result.deinit(self.allocator);

        var read_buffer: [4096]u8 = undefined;
        var reader = std.Io.File.Reader.init(file, io, &read_buffer);
        var chunk: [4096]u8 = undefined;

        while (result.items.len < max_size) {
            const remaining = max_size - result.items.len;
            const limit = @min(chunk.len, remaining);
            const bytes_read = try reader.interface.readSliceShort(chunk[0..limit]);
            if (bytes_read == 0) break;
            try result.appendSlice(self.allocator, chunk[0..bytes_read]);
        }

        return try result.toOwnedSlice(self.allocator);
    }

    pub fn createPackage(self: *PackageArchiver, io: Io, pkgbuild: *const parser.PkgBuild, pkg_dir: []const u8, output_path: []const u8) !void {
        print("==> Creating package archive: {s}\n", .{output_path});

        // Generate PKGINFO
        const pkg_info = try self.generatePackageInfo(io, pkgbuild, pkg_dir);
        const pkginfo_content = try pkg_info.generatePkgInfo(self.allocator);
        defer self.allocator.free(pkginfo_content);

        // Write PKGINFO to package directory
        const pkginfo_path = try std.fs.path.join(self.allocator, &[_][]const u8{ pkg_dir, ".PKGINFO" });
        defer self.allocator.free(pkginfo_path);

        var pkginfo_file = try Dir.cwd().createFile(io, pkginfo_path, .{});
        defer pkginfo_file.close(io);
        try pkginfo_file.writeStreamingAll(io, pkginfo_content);

        // Generate MTREE (file manifest)
        const mtree_content = try self.generateMtree(io, pkg_dir);
        defer self.allocator.free(mtree_content);

        const mtree_path = try std.fs.path.join(self.allocator, &[_][]const u8{ pkg_dir, ".MTREE" });
        defer self.allocator.free(mtree_path);

        var mtree_file = try Dir.cwd().createFile(io, mtree_path, .{});
        defer mtree_file.close(io);
        try mtree_file.writeStreamingAll(io, mtree_content);

        // Create tar.zst archive
        try self.createTarZst(io, pkg_dir, output_path);

        // Clean up metadata files
        Dir.cwd().deleteFile(io, pkginfo_path) catch {};
        Dir.cwd().deleteFile(io, mtree_path) catch {};

        // Get final package size
        const pkg_stat = try Dir.cwd().statFile(io, output_path, .{});
        print("✅ Package created: {s} ({d} KB)\n", .{ output_path, pkg_stat.size / 1024 });
    }

    fn generatePackageInfo(self: *PackageArchiver, io: Io, pkgbuild: *const parser.PkgBuild, pkg_dir: []const u8) !PackageInfo {
        const size = try self.calculateDirectorySize(io, pkg_dir);
        const builddate = std.Io.Timestamp.now(io, .real).toSeconds();

        // Determine architecture
        const arch = if (pkgbuild.arch.len > 0) pkgbuild.arch[0] else "any";

        return PackageInfo{
            .pkgname = pkgbuild.pkgname,
            .pkgver = pkgbuild.pkgver,
            .pkgrel = pkgbuild.pkgrel,
            .pkgdesc = pkgbuild.pkgdesc,
            .url = pkgbuild.url,
            .builddate = builddate,
            .packager = "zing <zing@localhost>",
            .size = size,
            .arch = arch,
            .license = pkgbuild.license,
            .depends = pkgbuild.depends,
        };
    }

    fn calculateDirectorySize(self: *PackageArchiver, io: Io, dir_path: []const u8) !u64 {
        var total_size: u64 = 0;

        var dir = Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return 0;
        defer dir.close(io);

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind == .file) {
                const stat = dir.statFile(io, entry.path, .{}) catch continue;
                total_size += stat.size;
            }
        }

        return total_size;
    }

    fn generateMtree(self: *PackageArchiver, io: Io, pkg_dir: []const u8) ![]const u8 {
        // MTREE header
        var content: ArrayList(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "#mtree\n");
        try content.appendSlice(self.allocator, "/set type=file uid=0 gid=0 mode=644\n");

        var dir = Dir.cwd().openDir(io, pkg_dir, .{ .iterate = true }) catch {
            return try self.allocator.dupe(u8, "#mtree\n");
        };
        defer dir.close(io);

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        var entries: ArrayList([]const u8) = .empty;
        defer {
            for (entries.items) |entry| self.allocator.free(entry);
            entries.deinit(self.allocator);
        }

        while (try walker.next(io)) |entry| {
            if (entry.kind == .file and !std.mem.startsWith(u8, entry.path, ".")) {
                const stat = dir.statFile(io, entry.path, .{}) catch continue;
                const digest = try self.fileSha256(io, dir, entry.path);
                defer self.allocator.free(digest);

                const mtree_entry = try std.fmt.allocPrint(self.allocator, "./{s} size={d} sha256digest={s}\n", .{ entry.path, stat.size, digest });
                try entries.append(self.allocator, mtree_entry);
            }
        }

        // Sort entries for reproducible builds
        std.mem.sort([]const u8, entries.items, {}, struct {
            fn lessThan(context: void, a: []const u8, b: []const u8) bool {
                _ = context;
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (entries.items) |entry| {
            try content.appendSlice(self.allocator, entry);
        }

        return try content.toOwnedSlice(self.allocator);
    }

    fn fileSha256(self: *PackageArchiver, io: Io, dir: Dir, relative_path: []const u8) ![]const u8 {
        var file = try dir.openFile(io, relative_path, .{});
        defer file.close(io);

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var read_buffer: [8192]u8 = undefined;
        var reader = std.Io.File.Reader.init(file, io, &read_buffer);
        var chunk: [8192]u8 = undefined;

        while (true) {
            const bytes_read = try reader.interface.readSliceShort(&chunk);
            if (bytes_read == 0) break;
            hasher.update(chunk[0..bytes_read]);
        }

        var hash_bytes: [32]u8 = undefined;
        hasher.final(&hash_bytes);

        return try std.fmt.allocPrint(self.allocator, "{x}", .{hash_bytes});
    }

    fn createTarZst(self: *PackageArchiver, io: Io, source_dir: []const u8, output_path: []const u8) !void {
        print("==> Compressing package with zstd (level {d})...\n", .{self.compression_level});

        const compression_arg = try std.fmt.allocPrint(self.allocator, "zstd -{d}", .{self.compression_level});
        defer self.allocator.free(compression_arg);

        var child = try std.process.spawn(io, .{
            .argv = &[_][]const u8{
                "tar",
                "--use-compress-program",
                compression_arg,
                "-cf",
                output_path,
                "-C",
                source_dir,
                ".",
            },
            .stderr = .pipe,
        });

        const stderr = try self.readFileAlloc(io, child.stderr.?, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait(io);

        if (result != .exited or result.exited != 0) {
            print("❌ tar command failed:\n{s}\n", .{stderr});
            return error.ArchiveCreationFailed;
        }
    }

    pub fn signPackage(self: *PackageArchiver, io: Io, package_path: []const u8, gpg_key: ?[]const u8) !void {
        const key_arg = gpg_key orelse {
            print("⚠️  No GPG key specified, skipping package signing\n", .{});
            return;
        };

        print("==> Signing package with GPG key: {s}\n", .{key_arg});

        const sig_path = try std.fmt.allocPrint(self.allocator, "{s}.sig", .{package_path});
        defer self.allocator.free(sig_path);

        var child = try std.process.spawn(io, .{
            .argv = &[_][]const u8{
                "gpg",
                "--detach-sign",
                "--use-agent",
                "--no-armor",
                "--local-user",
                key_arg,
                "--output",
                sig_path,
                package_path,
            },
        });

        const result = try child.wait(io);

        if (result != .exited or result.exited != 0) {
            print("❌ GPG signing failed\n", .{});
            return error.SigningFailed;
        }

        print("✅ Package signed: {s}\n", .{sig_path});
    }

    pub fn verifyPackage(self: *PackageArchiver, io: Io, package_path: []const u8) !bool {
        print("==> Verifying package integrity: {s}\n", .{package_path});

        // Test extraction without actually extracting
        var child = try std.process.spawn(io, .{
            .argv = &[_][]const u8{
                "tar",
                "--use-compress-program=zstd",
                "-tf",
                package_path,
            },
            .stdout = .pipe,
            .stderr = .pipe,
        });

        const stdout = try self.readFileAlloc(io, child.stdout.?, 1024 * 1024);
        defer self.allocator.free(stdout);

        const stderr = try self.readFileAlloc(io, child.stderr.?, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait(io);

        if (result != .exited or result.exited != 0) {
            print("❌ Package verification failed:\n{s}\n", .{stderr});
            return false;
        }

        // Check for required metadata files
        const has_pkginfo = std.mem.indexOf(u8, stdout, ".PKGINFO") != null;
        const has_mtree = std.mem.indexOf(u8, stdout, ".MTREE") != null;

        if (!has_pkginfo) {
            print("❌ Package missing .PKGINFO\n", .{});
            return false;
        }

        if (!has_mtree) {
            print("❌ Package missing .MTREE\n", .{});
            return false;
        }

        print("✅ Package verification passed\n", .{});
        return true;
    }
};

test "verifyPackage accepts archive with metadata files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "pkg/usr/bin");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "pkg/usr/bin/demo",
        .data = "#!/bin/sh\necho demo\n",
    });

    var pkgbuild = try parser.parsePkgBuild(std.testing.allocator,
        \\pkgname=demo
        \\pkgver=1.0.0
        \\pkgrel=1
        \\pkgdesc="demo"
        \\arch=('x86_64')
        \\license=('MIT')
    );
    defer pkgbuild.deinit();

    const root_path = try std.fs.path.join(std.testing.allocator, &.{ ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(root_path);

    const pkg_dir = try std.fs.path.join(std.testing.allocator, &.{ root_path, "pkg" });
    defer std.testing.allocator.free(pkg_dir);

    const out_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "demo-1.0.0-1-x86_64.pkg.tar.zst" });
    defer std.testing.allocator.free(out_path);

    var archiver = PackageArchiver.init(std.testing.allocator);
    try archiver.createPackage(std.testing.io, &pkgbuild, pkg_dir, out_path);
    try std.testing.expect(try archiver.verifyPackage(std.testing.io, out_path));
}
