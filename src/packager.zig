const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
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
        var content = ArrayList(u8).init(allocator);
        defer content.deinit();

        const writer = content.writer();

        try writer.print("pkgname = {s}\n", .{self.pkgname});
        try writer.print("pkgver = {s}\n", .{self.pkgver});
        try writer.print("pkgrel = {s}\n", .{self.pkgrel});

        if (self.pkgdesc) |desc| {
            try writer.print("pkgdesc = {s}\n", .{desc});
        }

        if (self.url) |u| {
            try writer.print("url = {s}\n", .{u});
        }

        try writer.print("builddate = {d}\n", .{self.builddate});
        try writer.print("packager = {s}\n", .{self.packager});
        try writer.print("size = {d}\n", .{self.size});
        try writer.print("arch = {s}\n", .{self.arch});

        for (self.license) |lic| {
            try writer.print("license = {s}\n", .{lic});
        }

        for (self.depends) |dep| {
            try writer.print("depend = {s}\n", .{dep});
        }

        return try content.toOwnedSlice();
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

    pub fn createPackage(self: *PackageArchiver, pkgbuild: *const parser.PkgBuild, pkg_dir: []const u8, output_path: []const u8) !void {
        print("==> Creating package archive: {s}\n", .{output_path});

        // Generate PKGINFO
        const pkg_info = try self.generatePackageInfo(pkgbuild, pkg_dir);
        const pkginfo_content = try pkg_info.generatePkgInfo(self.allocator);
        defer self.allocator.free(pkginfo_content);

        // Write PKGINFO to package directory
        const pkginfo_path = try std.fs.path.join(self.allocator, &[_][]const u8{ pkg_dir, ".PKGINFO" });
        defer self.allocator.free(pkginfo_path);

        var pkginfo_file = try std.fs.cwd().createFile(pkginfo_path, .{});
        defer pkginfo_file.close();
        try pkginfo_file.writeAll(pkginfo_content);

        // Generate MTREE (file manifest)
        const mtree_content = try self.generateMtree(pkg_dir);
        defer self.allocator.free(mtree_content);

        const mtree_path = try std.fs.path.join(self.allocator, &[_][]const u8{ pkg_dir, ".MTREE" });
        defer self.allocator.free(mtree_path);

        var mtree_file = try std.fs.cwd().createFile(mtree_path, .{});
        defer mtree_file.close();
        try mtree_file.writeAll(mtree_content);

        // Create tar.zst archive
        try self.createTarZst(pkg_dir, output_path);

        // Clean up metadata files
        std.fs.cwd().deleteFile(pkginfo_path) catch {};
        std.fs.cwd().deleteFile(mtree_path) catch {};

        // Get final package size
        const pkg_stat = try std.fs.cwd().statFile(output_path);
        print("✅ Package created: {s} ({d} KB)\n", .{ output_path, pkg_stat.size / 1024 });
    }

    fn generatePackageInfo(self: *PackageArchiver, pkgbuild: *const parser.PkgBuild, pkg_dir: []const u8) !PackageInfo {
        const size = try self.calculateDirectorySize(pkg_dir);

        // Determine architecture
        const arch = if (pkgbuild.arch.len > 0) pkgbuild.arch[0] else "any";

        return PackageInfo{
            .pkgname = pkgbuild.pkgname,
            .pkgver = pkgbuild.pkgver,
            .pkgrel = pkgbuild.pkgrel,
            .pkgdesc = pkgbuild.pkgdesc,
            .url = pkgbuild.url,
            .builddate = std.time.timestamp(),
            .packager = "zmake <zmake@localhost>",
            .size = size,
            .arch = arch,
            .license = pkgbuild.license,
            .depends = pkgbuild.depends,
        };
    }

    fn calculateDirectorySize(self: *PackageArchiver, dir_path: []const u8) !u64 {
        var total_size: u64 = 0;

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return 0;
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind == .file) {
                const stat = dir.statFile(entry.path) catch continue;
                total_size += stat.size;
            }
        }

        return total_size;
    }

    fn generateMtree(self: *PackageArchiver, pkg_dir: []const u8) ![]const u8 {
        var content = ArrayList(u8).init(self.allocator);
        defer content.deinit();

        const writer = content.writer();

        // MTREE header
        try writer.writeAll("#mtree\n");
        try writer.writeAll("/set type=file uid=0 gid=0 mode=644\n");

        var dir = std.fs.cwd().openDir(pkg_dir, .{ .iterate = true }) catch {
            return try self.allocator.dupe(u8, "#mtree\n");
        };
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        var entries = ArrayList([]const u8).init(self.allocator);
        defer {
            for (entries.items) |entry| self.allocator.free(entry);
            entries.deinit();
        }

        while (try walker.next()) |entry| {
            if (entry.kind == .file and !std.mem.startsWith(u8, entry.path, ".")) {
                const stat = dir.statFile(entry.path) catch continue;

                const mtree_entry = try std.fmt.allocPrint(self.allocator, "./{s} size={d} md5digest={s}\n", .{ entry.path, stat.size, "00000000000000000000000000000000" } // Placeholder MD5
                );
                try entries.append(mtree_entry);
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
            try writer.writeAll(entry);
        }

        return try content.toOwnedSlice();
    }

    fn createTarZst(self: *PackageArchiver, source_dir: []const u8, output_path: []const u8) !void {
        print("==> Compressing package with zstd (level {d})...\n", .{self.compression_level});

        const compression_arg = try std.fmt.allocPrint(self.allocator, "zstd -{d}", .{self.compression_level});
        defer self.allocator.free(compression_arg);

        var child = std.process.Child.init(&[_][]const u8{
            "tar",
            "--use-compress-program",
            compression_arg,
            "-cf",
            output_path,
            "-C",
            source_dir,
            ".",
        }, self.allocator);

        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait();

        if (result != .Exited or result.Exited != 0) {
            print("❌ tar command failed:\n{s}\n", .{stderr});
            return error.ArchiveCreationFailed;
        }
    }

    pub fn signPackage(self: *PackageArchiver, package_path: []const u8, gpg_key: ?[]const u8) !void {
        const key_arg = gpg_key orelse {
            print("⚠️  No GPG key specified, skipping package signing\n", .{});
            return;
        };

        print("==> Signing package with GPG key: {s}\n", .{key_arg});

        const sig_path = try std.fmt.allocPrint(self.allocator, "{s}.sig", .{package_path});
        defer self.allocator.free(sig_path);

        var child = std.process.Child.init(&[_][]const u8{
            "gpg",
            "--detach-sign",
            "--use-agent",
            "--no-armor",
            "--local-user",
            key_arg,
            "--output",
            sig_path,
            package_path,
        }, self.allocator);

        const result = try child.spawnAndWait();

        if (result != .Exited or result.Exited != 0) {
            print("❌ GPG signing failed\n", .{});
            return error.SigningFailed;
        }

        print("✅ Package signed: {s}\n", .{sig_path});
    }

    pub fn verifyPackage(self: *PackageArchiver, package_path: []const u8) !bool {
        print("==> Verifying package integrity: {s}\n", .{package_path});

        // Test extraction without actually extracting
        var child = std.process.Child.init(&[_][]const u8{
            "tar",
            "--use-compress-program=zstd",
            "-tf",
            package_path,
        }, self.allocator);

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);

        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait();

        if (result != .Exited or result.Exited != 0) {
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
