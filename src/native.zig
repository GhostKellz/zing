const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const ProjectType = enum {
    zig,
    c,
    cpp,
    mixed,
    unknown,
};

pub const ZigProject = struct {
    allocator: Allocator,
    name: []const u8,
    version: []const u8,
    root_dir: []const u8,

    pub fn deinit(self: *ZigProject) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.root_dir);
    }
};

pub const CProject = struct {
    allocator: Allocator,
    name: []const u8,
    version: []const u8,
    root_dir: []const u8,
    sources: [][]const u8,
    headers: [][]const u8,

    pub fn deinit(self: *CProject) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.root_dir);
        for (self.sources) |s| self.allocator.free(s);
        self.allocator.free(self.sources);
        for (self.headers) |h| self.allocator.free(h);
        self.allocator.free(self.headers);
    }
};

pub const NativeProject = union {
    zig: ZigProject,
    c: CProject,
};

fn readFileAlloc(allocator: Allocator, file: std.fs.File, max_size: usize) ![]u8 {
    const stat = try file.stat();
    const size: usize = @intCast(@min(stat.size, max_size));
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    var total_read: usize = 0;
    while (total_read < size) {
        const bytes_read = try file.read(buffer[total_read..]);
        if (bytes_read == 0) break;
        total_read += bytes_read;
    }
    return buffer[0..total_read];
}

pub fn detectProjectType(allocator: Allocator, project_dir: []const u8) !ProjectType {
    _ = allocator;

    var dir = std.fs.cwd().openDir(project_dir, .{ .iterate = true }) catch {
        return .unknown;
    };
    defer dir.close();

    var has_zig = false;
    var has_c = false;
    var has_cpp = false;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.eql(u8, entry.name, "build.zig")) {
                has_zig = true;
            } else if (std.mem.endsWith(u8, entry.name, ".zig")) {
                has_zig = true;
            } else if (std.mem.endsWith(u8, entry.name, ".c")) {
                has_c = true;
            } else if (std.mem.endsWith(u8, entry.name, ".cpp") or
                std.mem.endsWith(u8, entry.name, ".cc") or
                std.mem.endsWith(u8, entry.name, ".cxx"))
            {
                has_cpp = true;
            }
        }
    }

    if (has_zig and (has_c or has_cpp)) return .mixed;
    if (has_zig) return .zig;
    if (has_cpp) return .cpp;
    if (has_c) return .c;
    return .unknown;
}

pub fn analyzeZigProject(allocator: Allocator, project_dir: []const u8) !ZigProject {
    var project = ZigProject{
        .allocator = allocator,
        .name = try allocator.dupe(u8, "zig-project"),
        .version = try allocator.dupe(u8, "0.1.0"),
        .root_dir = try allocator.dupe(u8, project_dir),
    };

    // Try to read build.zig.zon for project info
    const zon_path = try std.fs.path.join(allocator, &[_][]const u8{ project_dir, "build.zig.zon" });
    defer allocator.free(zon_path);

    if (std.fs.cwd().openFile(zon_path, .{})) |file| {
        defer file.close();
        const content = readFileAlloc(allocator, file, 1024 * 1024) catch null;
        if (content) |c| {
            defer allocator.free(c);

            // Simple name extraction
            if (std.mem.indexOf(u8, c, ".name = .")) |pos| {
                const start = pos + 9;
                if (std.mem.indexOfPos(u8, c, start, ",")) |end| {
                    allocator.free(project.name);
                    project.name = try allocator.dupe(u8, c[start..end]);
                }
            }

            // Simple version extraction
            if (std.mem.indexOf(u8, c, ".version = \"")) |pos| {
                const start = pos + 12;
                if (std.mem.indexOfPos(u8, c, start, "\"")) |end| {
                    allocator.free(project.version);
                    project.version = try allocator.dupe(u8, c[start..end]);
                }
            }
        }
    } else |_| {}

    return project;
}

pub fn analyzeCProject(allocator: Allocator, project_dir: []const u8) !CProject {
    var sources: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (sources.items) |s| allocator.free(s);
        sources.deinit(allocator);
    }

    var headers: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (headers.items) |h| allocator.free(h);
        headers.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(project_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.name, ".c") or
                std.mem.endsWith(u8, entry.name, ".cpp") or
                std.mem.endsWith(u8, entry.name, ".cc"))
            {
                try sources.append(allocator, try allocator.dupe(u8, entry.name));
            } else if (std.mem.endsWith(u8, entry.name, ".h") or
                std.mem.endsWith(u8, entry.name, ".hpp"))
            {
                try headers.append(allocator, try allocator.dupe(u8, entry.name));
            }
        }
    }

    // Extract project name from directory
    const name = std.fs.path.basename(project_dir);

    return CProject{
        .allocator = allocator,
        .name = try allocator.dupe(u8, if (name.len > 0) name else "c-project"),
        .version = try allocator.dupe(u8, "0.1.0"),
        .root_dir = try allocator.dupe(u8, project_dir),
        .sources = try sources.toOwnedSlice(allocator),
        .headers = try headers.toOwnedSlice(allocator),
    };
}

pub fn buildZigProject(allocator: Allocator, project: *ZigProject, target: ?[]const u8, release_mode: bool) !void {
    print("==> Building with zig build\n", .{});

    var args: std.ArrayListUnmanaged([]const u8) = .{};
    defer args.deinit(allocator);

    try args.append(allocator, "zig");
    try args.append(allocator, "build");

    if (release_mode) {
        try args.append(allocator, "-Doptimize=ReleaseFast");
    }

    if (target) |t| {
        const target_arg = try std.fmt.allocPrint(allocator, "-Dtarget={s}", .{t});
        defer allocator.free(target_arg);
        try args.append(allocator, target_arg);
    }

    var child = std.process.Child.init(args.items, allocator);
    if (project.root_dir.len > 0 and !std.mem.eql(u8, project.root_dir, ".")) {
        child.cwd = project.root_dir;
    }
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const result = try child.spawnAndWait();
    if (result.Exited != 0) {
        return error.BuildFailed;
    }

    print("==> Build successful\n", .{});
}

pub fn buildCProject(allocator: Allocator, project: *CProject, target: ?[]const u8, release_mode: bool) !void {
    print("==> Building C/C++ project with zig cc\n", .{});

    if (project.sources.len == 0) {
        print("   No source files found\n", .{});
        return error.NoSources;
    }

    var args: std.ArrayListUnmanaged([]const u8) = .{};
    defer args.deinit(allocator);

    try args.append(allocator, "zig");
    try args.append(allocator, "cc");

    // Add source files
    for (project.sources) |src| {
        try args.append(allocator, src);
    }

    try args.append(allocator, "-o");
    try args.append(allocator, project.name);

    if (release_mode) {
        try args.append(allocator, "-O2");
    }

    if (target) |t| {
        const target_arg = try std.fmt.allocPrint(allocator, "-target={s}", .{t});
        defer allocator.free(target_arg);
        try args.append(allocator, target_arg);
    }

    var child = std.process.Child.init(args.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const result = try child.spawnAndWait();
    if (result.Exited != 0) {
        return error.BuildFailed;
    }

    print("==> Build successful: {s}\n", .{project.name});
}

pub fn createNativePackage(allocator: Allocator, project: *NativeProject, output_dir: []const u8) !void {
    _ = allocator;
    _ = project;
    print("==> Creating package in: {s}\n", .{output_dir});
    // TODO: Implement package creation
}
