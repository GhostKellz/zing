const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const deps = @import("deps.zig");

pub const AurPackage = struct {
    name: []const u8,
    version: []const u8,
    description: ?[]const u8,
    url: ?[]const u8,
    clone_url: []const u8,
    dependencies: [][]const u8,
    make_dependencies: [][]const u8,

    allocator: Allocator,

    pub fn deinit(self: *AurPackage) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        if (self.description) |desc| self.allocator.free(desc);
        if (self.url) |url| self.allocator.free(url);
        self.allocator.free(self.clone_url);
        for (self.dependencies) |dep| self.allocator.free(dep);
        self.allocator.free(self.dependencies);
        for (self.make_dependencies) |dep| self.allocator.free(dep);
        self.allocator.free(self.make_dependencies);
    }
};

pub const AurClient = struct {
    allocator: Allocator,
    cache_dir: []const u8,

    pub fn init(allocator: Allocator) !AurClient {
        const cache_dir = try std.fs.path.join(allocator, &[_][]const u8{ std.os.getenv("HOME") orelse "/tmp", ".cache", "zmake", "aur" });

        // Create cache directory
        std.fs.cwd().makePath(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return AurClient{
            .allocator = allocator,
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *AurClient) void {
        self.allocator.free(self.cache_dir);
    }

    pub fn searchPackage(self: *AurClient, package_name: []const u8) !?AurPackage {
        print("==> Searching AUR for: {s}\n", .{package_name});

        // Query AUR RPC API
        const url = try std.fmt.allocPrint(self.allocator, "https://aur.archlinux.org/rpc/?v=5&type=info&arg={s}", .{package_name});
        defer self.allocator.free(url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return null;

        var request = client.open(.GET, uri, .{
            .server_header_buffer = try self.allocator.alloc(u8, 8192),
        }) catch return null;
        defer request.deinit();

        request.send() catch return null;
        request.wait() catch return null;

        if (request.response.status != .ok) return null;

        const response_body = request.readAll(self.allocator, 1024 * 1024) catch return null;
        defer self.allocator.free(response_body);

        // Parse JSON response (simplified)
        return self.parseAurResponse(package_name, response_body);
    }

    fn parseAurResponse(self: *AurClient, package_name: []const u8, json_data: []const u8) !?AurPackage {
        // Simplified JSON parsing - in production use a proper JSON parser
        if (std.mem.indexOf(u8, json_data, "\"resultcount\":0")) |_| {
            print("❌ Package {s} not found in AUR\n", .{package_name});
            return null;
        }

        // Extract basic info (very simplified parsing)
        const name = try self.allocator.dupe(u8, package_name);
        const version = try self.extractJsonField(json_data, "Version") orelse try self.allocator.dupe(u8, "unknown");
        const description = try self.extractJsonField(json_data, "Description");
        const url_field = try self.extractJsonField(json_data, "URL");

        const clone_url = try std.fmt.allocPrint(self.allocator, "https://aur.archlinux.org/{s}.git", .{package_name});

        print("✅ Found in AUR: {s} v{s}\n", .{ name, version });

        return AurPackage{
            .name = name,
            .version = version,
            .description = description,
            .url = url_field,
            .clone_url = clone_url,
            .dependencies = &[_][]const u8{}, // TODO: Parse from JSON
            .make_dependencies = &[_][]const u8{},
            .allocator = self.allocator,
        };
    }

    fn extractJsonField(self: *AurClient, json_data: []const u8, field_name: []const u8) !?[]const u8 {
        const field_search = try std.fmt.allocPrint(self.allocator, "\"{s}\":", .{field_name});
        defer self.allocator.free(field_search);

        if (std.mem.indexOf(u8, json_data, field_search)) |start_pos| {
            const value_start = start_pos + field_search.len;

            // Skip whitespace and quote
            var pos = value_start;
            while (pos < json_data.len and (json_data[pos] == ' ' or json_data[pos] == '"')) {
                pos += 1;
            }

            // Find end quote
            const value_end = std.mem.indexOfPos(u8, json_data, pos, "\"") orelse return null;

            if (pos < value_end) {
                return try self.allocator.dupe(u8, json_data[pos..value_end]);
            }
        }

        return null;
    }

    pub fn clonePackage(self: *AurClient, package: *const AurPackage) ![]const u8 {
        const clone_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, package.name });

        print("==> Cloning AUR package: {s}\n", .{package.name});

        // Remove existing directory if it exists
        std.fs.cwd().deleteTree(clone_dir) catch {};

        // Clone the repository
        var child = std.process.Child.init(&[_][]const u8{ "git", "clone", package.clone_url, clone_dir }, self.allocator);

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);

        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait();

        if (result != .Exited or result.Exited != 0) {
            print("❌ Failed to clone AUR package:\n{s}\n", .{stderr});
            return error.CloneFailed;
        }

        print("✅ Cloned to: {s}\n", .{clone_dir});
        return clone_dir;
    }

    pub fn resolveDependencies(self: *AurClient, package_names: []const []const u8) ![][]const u8 {
        print("==> Resolving AUR dependencies...\n", .{});

        var resolved = ArrayList([]const u8).init(self.allocator);
        defer resolved.deinit();

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        // Recursive dependency resolution
        for (package_names) |pkg_name| {
            try self.resolveDependencyRecursive(pkg_name, &resolved, &visited);
        }

        return try resolved.toOwnedSlice();
    }

    fn resolveDependencyRecursive(self: *AurClient, package_name: []const u8, resolved: *ArrayList([]const u8), visited: *std.StringHashMap(void)) !void {
        if (visited.contains(package_name)) return;

        try visited.put(try self.allocator.dupe(u8, package_name), {});

        if (try self.searchPackage(package_name)) |aur_pkg| {
            defer aur_pkg.deinit();

            // First resolve dependencies
            for (aur_pkg.dependencies) |dep| {
                try self.resolveDependencyRecursive(dep, resolved, visited);
            }

            for (aur_pkg.make_dependencies) |dep| {
                try self.resolveDependencyRecursive(dep, resolved, visited);
            }

            // Then add this package
            try resolved.append(try self.allocator.dupe(u8, package_name));
            print("   📦 {s}\n", .{package_name});
        } else {
            print("⚠️  AUR package not found: {s}\n", .{package_name});
        }
    }

    pub fn buildAurPackage(self: *AurClient, package: *const AurPackage, clone_dir: []const u8) !void {
        print("==> Building AUR package: {s}\n", .{package.name});

        // Change to package directory
        const pkgbuild_path = try std.fs.path.join(self.allocator, &[_][]const u8{ clone_dir, "PKGBUILD" });
        defer self.allocator.free(pkgbuild_path);

        // Check if PKGBUILD exists
        std.fs.cwd().access(pkgbuild_path, .{}) catch {
            print("❌ PKGBUILD not found in: {s}\n", .{clone_dir});
            return error.NoPkgBuild;
        };

        // Build with makepkg (for now, later integrate with zmake)
        var child = std.process.Child.init(&[_][]const u8{ "makepkg", "-si", "--noconfirm" }, self.allocator);

        child.cwd = clone_dir;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const result = try child.spawnAndWait();

        if (result != .Exited or result.Exited != 0) {
            print("❌ Failed to build AUR package: {s}\n", .{package.name});
            return error.BuildFailed;
        }

        print("✅ Successfully built and installed: {s}\n", .{package.name});
    }
};

pub fn installAurDependencies(allocator: Allocator, aur_deps: []const []const u8) !void {
    if (aur_deps.len == 0) return;

    print("==> Installing AUR dependencies...\n", .{});

    var aur_client = try AurClient.init(allocator);
    defer aur_client.deinit();

    // Resolve all dependencies in correct order
    const resolved_deps = try aur_client.resolveDependencies(aur_deps);
    defer {
        for (resolved_deps) |dep| allocator.free(dep);
        allocator.free(resolved_deps);
    }

    print("==> Build order: {d} packages\n", .{resolved_deps.len});

    // Build and install each package
    for (resolved_deps) |pkg_name| {
        if (try aur_client.searchPackage(pkg_name)) |aur_pkg| {
            defer aur_pkg.deinit();

            const clone_dir = try aur_client.clonePackage(&aur_pkg);
            defer allocator.free(clone_dir);

            try aur_client.buildAurPackage(&aur_pkg, clone_dir);
        }
    }

    print("🎉 All AUR dependencies installed successfully!\n", .{});
}

pub fn checkAurUpdates(allocator: Allocator, packages: []const []const u8) !void {
    print("==> Checking AUR packages for updates...\n", .{});

    var aur_client = try AurClient.init(allocator);
    defer aur_client.deinit();

    for (packages) |pkg_name| {
        if (try aur_client.searchPackage(pkg_name)) |aur_pkg| {
            defer aur_pkg.deinit();
            print("   {s}: {s}\n", .{ aur_pkg.name, aur_pkg.version });
        }
    }
}
