const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;

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
    io: Io,
    installed_packages: std.StringHashMap(PackageInfo),
    package_db_available: bool,

    pub fn init(allocator: Allocator, io: Io) !DependencyResolver {
        const package_db_available = hasPacman(io) catch false;
        return DependencyResolver{
            .allocator = allocator,
            .io = io,
            .installed_packages = std.StringHashMap(PackageInfo).init(allocator),
            .package_db_available = package_db_available,
        };
    }

    pub fn deinit(self: *DependencyResolver) void {
        var iterator = self.installed_packages.iterator();
        while (iterator.next()) |entry| {
            var pkg_info = entry.value_ptr;
            pkg_info.deinit(self.allocator);
        }
        self.installed_packages.deinit();
    }

    fn readFileAlloc(self: *DependencyResolver, file: std.Io.File, max_size: usize) ![]u8 {
        var result: ArrayList(u8) = .empty;
        defer result.deinit(self.allocator);

        var read_buffer: [4096]u8 = undefined;
        var reader = std.Io.File.Reader.init(file, self.io, &read_buffer);
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

    pub fn checkDependencies(self: *DependencyResolver, deps: []const []const u8) ![]Dependency {
        if (!self.package_db_available) {
            print("⚠️  Skipping dependency preflight because pacman is unavailable\n", .{});
            return try self.allocator.alloc(Dependency, 0);
        }

        if (deps.len == 0) {
            return try self.allocator.alloc(Dependency, 0);
        }

        print("==> Checking dependencies...\n", .{});

        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, "pacman");
        try argv.append(self.allocator, "-T");
        try argv.appendSlice(self.allocator, deps);

        var child = try std.process.spawn(self.io, .{
            .argv = argv.items,
            .stdout = .pipe,
            .stderr = .pipe,
        });

        const stdout = try self.readFileAlloc(child.stdout.?, 1024 * 1024);
        defer self.allocator.free(stdout);

        const stderr = try self.readFileAlloc(child.stderr.?, 1024 * 1024);
        defer self.allocator.free(stderr);

        const result = try child.wait(self.io);
        if (result != .exited) return error.DependencyCheckFailed;
        if (result.exited != 0 and stdout.len == 0) {
            if (stderr.len > 0) print("⚠️  pacman -T failed:\n{s}\n", .{stderr});
            return error.DependencyCheckFailed;
        }

        var missing_deps: ArrayList(Dependency) = .empty;
        defer missing_deps.deinit(self.allocator);

        var missing_lines = std.mem.splitScalar(u8, stdout, '\n');
        while (missing_lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            const dep = try Dependency.parse(self.allocator, trimmed);
            print("❌ Missing dependency: {s}\n", .{trimmed});
            try missing_deps.append(self.allocator, dep);
        }

        if (missing_deps.items.len == 0) {
            for (deps) |dep| {
                print("✅ Dependency satisfied: {s}\n", .{dep});
            }
        }

        return try missing_deps.toOwnedSlice(self.allocator);
    }

    pub fn suggestAURPackages(self: *DependencyResolver, missing_deps: []const Dependency) !void {
        _ = self;

        if (missing_deps.len == 0) return;

        print("\n==> If any missing dependencies are AUR-only, install them with your preferred helper. Example:\n", .{});
        for (missing_deps) |dep| {
            print("    yay -S {s}\n", .{dep.name});
        }
        print("    Use pacman for official repo packages when available.\n", .{});
    }
};

fn hasPacman(io: Io) !bool {
    var child = std.process.spawn(io, .{
        .argv = &[_][]const u8{ "pacman", "-V" },
    }) catch return false;

    const result = try child.wait(io);
    return result == .exited and result.exited == 0;
}

pub fn checkConflicts(allocator: Allocator, conflicts: []const []const u8, resolver: *DependencyResolver) ![][]const u8 {
    var conflicting = ArrayList([]const u8).init(allocator);
    defer conflicting.deinit();

    if (conflicts.len == 0) return &[_][]const u8{};
    if (!resolver.package_db_available) return &[_][]const u8{};

    print("==> Checking for conflicts...\n", .{});
    for (conflicts) |conflict_name| {
        var child = std.process.spawn(resolver.io, .{
            .argv = &[_][]const u8{ "pacman", "-Q", conflict_name },
        }) catch continue;
        const result = child.wait(resolver.io) catch continue;
        if (result == .exited and result.exited == 0) {
            print("⚠️  Conflict detected: {s} is installed\n", .{conflict_name});
            try conflicting.append(try allocator.dupe(u8, conflict_name));
        }
    }

    return try conflicting.toOwnedSlice();
}
