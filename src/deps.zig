const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const VersionConstraint = enum {
    none,
    equal,
    greater_equal,
    less_equal,
    greater,
    less,
};

pub const Dependency = struct {
    name: []const u8,
    version: ?[]const u8,
    constraint: VersionConstraint,

    pub fn parse(allocator: Allocator, dep_string: []const u8) !Dependency {
        // Parse dependency strings like "gcc>=4.7", "python=3.9", "glibc"
        var name = dep_string;
        var version: ?[]const u8 = null;
        var constraint = VersionConstraint.none;

        if (std.mem.indexOf(u8, dep_string, ">=")) |pos| {
            name = dep_string[0..pos];
            version = try allocator.dupe(u8, dep_string[pos + 2 ..]);
            constraint = .greater_equal;
        } else if (std.mem.indexOf(u8, dep_string, "<=")) |pos| {
            name = dep_string[0..pos];
            version = try allocator.dupe(u8, dep_string[pos + 2 ..]);
            constraint = .less_equal;
        } else if (std.mem.indexOf(u8, dep_string, ">")) |pos| {
            name = dep_string[0..pos];
            version = try allocator.dupe(u8, dep_string[pos + 1 ..]);
            constraint = .greater;
        } else if (std.mem.indexOf(u8, dep_string, "<")) |pos| {
            name = dep_string[0..pos];
            version = try allocator.dupe(u8, dep_string[pos + 1 ..]);
            constraint = .less;
        } else if (std.mem.indexOf(u8, dep_string, "=")) |pos| {
            name = dep_string[0..pos];
            version = try allocator.dupe(u8, dep_string[pos + 1 ..]);
            constraint = .equal;
        }

        return Dependency{
            .name = try allocator.dupe(u8, name),
            .version = version,
            .constraint = constraint,
        };
    }

    pub fn deinit(self: *Dependency, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.version) |v| allocator.free(v);
    }
};

pub const PackageInfo = struct {
    name: []const u8,
    version: []const u8,
    installed: bool,

    pub fn deinit(self: *PackageInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
    }
};

pub const DependencyResolver = struct {
    allocator: Allocator,
    installed_packages: std.StringHashMap(PackageInfo),

    pub fn init(allocator: Allocator) !DependencyResolver {
        var resolver = DependencyResolver{
            .allocator = allocator,
            .installed_packages = std.StringHashMap(PackageInfo).init(allocator),
        };

        try resolver.loadInstalledPackages();
        return resolver;
    }

    pub fn deinit(self: *DependencyResolver) void {
        var iterator = self.installed_packages.iterator();
        while (iterator.next()) |entry| {
            var pkg_info = entry.value_ptr;
            pkg_info.deinit(self.allocator);
        }
        self.installed_packages.deinit();
    }

    fn loadInstalledPackages(self: *DependencyResolver) !void {
        print("==> Loading installed packages from pacman database...\n", .{});

        // Query pacman for installed packages
        var child = std.process.Child.init(&[_][]const u8{ "pacman", "-Q" }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        child.spawn() catch |err| {
            print("⚠️  Could not query pacman database: {}\n", .{err});
            return;
        };

        const stdout = child.stdout.?.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            print("⚠️  Failed to read pacman output\n", .{});
            return;
        };
        defer self.allocator.free(stdout);

        const result = child.wait() catch {
            print("⚠️  Pacman query failed\n", .{});
            return;
        };

        if (result != .Exited or result.Exited != 0) {
            print("⚠️  Pacman returned error code\n", .{});
            return;
        }

        // Parse pacman output (format: "package-name version")
        var lines = std.mem.splitScalar(u8, stdout, '\n');
        var count: u32 = 0;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            var parts = std.mem.splitScalar(u8, trimmed, ' ');
            const name = parts.next() orelse continue;
            const version = parts.next() orelse continue;

            const pkg_info = PackageInfo{
                .name = try self.allocator.dupe(u8, name),
                .version = try self.allocator.dupe(u8, version),
                .installed = true,
            };

            try self.installed_packages.put(try self.allocator.dupe(u8, name), pkg_info);
            count += 1;
        }

        print("✅ Loaded {d} installed packages\n", .{count});
    }

    pub fn checkDependencies(self: *DependencyResolver, deps: []const []const u8) ![]Dependency {
        var missing_deps = ArrayList(Dependency).init(self.allocator);
        defer missing_deps.deinit();

        print("==> Checking dependencies...\n", .{});

        for (deps) |dep_string| {
            var dep = try Dependency.parse(self.allocator, dep_string);

            const installed_pkg = self.installed_packages.get(dep.name);

            if (installed_pkg == null) {
                print("❌ Missing dependency: {s}\n", .{dep.name});
                try missing_deps.append(dep);
                continue;
            }

            const pkg = installed_pkg.?;

            // Check version constraints
            if (dep.version != null) {
                const satisfies = try self.checkVersionConstraint(pkg.version, dep.version.?, dep.constraint);
                if (!satisfies) {
                    print("❌ Version constraint not satisfied: {s} (installed: {s}, required: {s}{s})\n", .{
                        dep.name,
                        pkg.version,
                        @tagName(dep.constraint),
                        dep.version.?,
                    });
                    try missing_deps.append(dep);
                    continue;
                }
            }

            print("✅ Dependency satisfied: {s} ({s})\n", .{ dep.name, pkg.version });
            dep.deinit(self.allocator);
        }

        return try missing_deps.toOwnedSlice();
    }

    fn checkVersionConstraint(self: *DependencyResolver, installed: []const u8, required: []const u8, constraint: VersionConstraint) !bool {
        _ = self;

        switch (constraint) {
            .none => return true,
            .equal => return std.mem.eql(u8, installed, required),
            .greater_equal => return try compareVersions(installed, required) >= 0,
            .less_equal => return try compareVersions(installed, required) <= 0,
            .greater => return try compareVersions(installed, required) > 0,
            .less => return try compareVersions(installed, required) < 0,
        }
    }

    pub fn suggestAURPackages(self: *DependencyResolver, missing_deps: []const Dependency) !void {
        _ = self;

        if (missing_deps.len == 0) return;

        print("\n==> Missing dependencies can potentially be found in AUR:\n", .{});
        for (missing_deps) |dep| {
            print("    yay -S {s}\n", .{dep.name});
        }
        print("💡 Run these commands or implement AUR support in zmake\n", .{});
    }
};

fn compareVersions(v1: []const u8, v2: []const u8) !i8 {
    // Simple version comparison (could be more sophisticated)
    var parts1 = std.mem.splitSequence(u8, v1, ".");
    var parts2 = std.mem.splitSequence(u8, v2, ".");

    while (true) {
        const p1 = parts1.next();
        const p2 = parts2.next();

        if (p1 == null and p2 == null) return 0;
        if (p1 == null) return -1;
        if (p2 == null) return 1;

        const n1 = std.fmt.parseInt(u32, p1.?, 10) catch 0;
        const n2 = std.fmt.parseInt(u32, p2.?, 10) catch 0;

        if (n1 < n2) return -1;
        if (n1 > n2) return 1;
    }
}

pub fn checkConflicts(allocator: Allocator, conflicts: []const []const u8, resolver: *DependencyResolver) ![][]const u8 {
    var conflicting = ArrayList([]const u8).init(allocator);
    defer conflicting.deinit();

    if (conflicts.len == 0) return &[_][]const u8{};

    print("==> Checking for conflicts...\n", .{});

    for (conflicts) |conflict_name| {
        if (resolver.installed_packages.contains(conflict_name)) {
            print("⚠️  Conflict detected: {s} is installed\n", .{conflict_name});
            try conflicting.append(try allocator.dupe(u8, conflict_name));
        }
    }

    return try conflicting.toOwnedSlice();
}
