const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const PkgBuild = struct {
    pkgname: []const u8,
    pkgver: []const u8,
    pkgrel: []const u8,
    pkgdesc: ?[]const u8,
    arch: [][]const u8,
    url: ?[]const u8,
    license: [][]const u8,
    depends: [][]const u8,
    makedepends: [][]const u8,
    source: [][]const u8,
    sha256sums: [][]const u8,

    allocator: Allocator,

    pub fn deinit(self: *PkgBuild) void {
        self.allocator.free(self.pkgname);
        self.allocator.free(self.pkgver);
        self.allocator.free(self.pkgrel);
        if (self.pkgdesc) |desc| self.allocator.free(desc);
        if (self.url) |u| self.allocator.free(u);

        for (self.arch) |item| self.allocator.free(item);
        self.allocator.free(self.arch);

        for (self.license) |item| self.allocator.free(item);
        self.allocator.free(self.license);

        for (self.depends) |item| self.allocator.free(item);
        self.allocator.free(self.depends);

        for (self.makedepends) |item| self.allocator.free(item);
        self.allocator.free(self.makedepends);

        for (self.source) |item| self.allocator.free(item);
        self.allocator.free(self.source);

        for (self.sha256sums) |item| self.allocator.free(item);
        self.allocator.free(self.sha256sums);
    }
};

pub fn parsePkgBuild(allocator: Allocator, content: []const u8) !PkgBuild {
    var pkgbuild = PkgBuild{
        .pkgname = "",
        .pkgver = "",
        .pkgrel = "",
        .pkgdesc = null,
        .arch = &[_][]const u8{},
        .url = null,
        .license = &[_][]const u8{},
        .depends = &[_][]const u8{},
        .makedepends = &[_][]const u8{},
        .source = &[_][]const u8{},
        .sha256sums = &[_][]const u8{},
        .allocator = allocator,
    };

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "pkgname=")) {
            pkgbuild.pkgname = try parseSimpleValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "pkgver=")) {
            pkgbuild.pkgver = try parseSimpleValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "pkgrel=")) {
            pkgbuild.pkgrel = try parseSimpleValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "pkgdesc=")) {
            pkgbuild.pkgdesc = try parseSimpleValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "url=")) {
            pkgbuild.url = try parseSimpleValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "arch=(")) {
            pkgbuild.arch = try parseArrayValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "license=(")) {
            pkgbuild.license = try parseArrayValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "depends=(")) {
            pkgbuild.depends = try parseArrayValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "makedepends=(")) {
            pkgbuild.makedepends = try parseArrayValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "source=(")) {
            pkgbuild.source = try parseArrayValue(allocator, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "sha256sums=(")) {
            pkgbuild.sha256sums = try parseArrayValue(allocator, trimmed);
        }
    }

    return pkgbuild;
}

fn parseSimpleValue(allocator: Allocator, line: []const u8) ![]const u8 {
    const eq_pos = std.mem.indexOf(u8, line, "=") orelse return error.InvalidFormat;
    var value = line[eq_pos + 1 ..];

    // Remove quotes if present
    if (value.len >= 2 and
        ((value[0] == '"' and value[value.len - 1] == '"') or
            (value[0] == '\'' and value[value.len - 1] == '\'')))
    {
        value = value[1 .. value.len - 1];
    }

    return try allocator.dupe(u8, value);
}

fn parseArrayValue(allocator: Allocator, line: []const u8) ![][]const u8 {
    const start = std.mem.indexOf(u8, line, "(") orelse return error.InvalidFormat;
    const end = std.mem.lastIndexOf(u8, line, ")") orelse return error.InvalidFormat;

    if (start >= end) return &[_][]const u8{};

    const content = std.mem.trim(u8, line[start + 1 .. end], " \t");
    if (content.len == 0) return &[_][]const u8{};

    var result: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    var items = std.mem.splitScalar(u8, content, ' ');
    while (items.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t'\"");
        if (trimmed.len > 0) {
            try result.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }

    return try result.toOwnedSlice(allocator);
}

pub fn validatePkgBuild(pkgbuild: *const PkgBuild) !void {
    if (pkgbuild.pkgname.len == 0) {
        return error.MissingPkgName;
    }
    if (pkgbuild.pkgver.len == 0) {
        return error.MissingPkgVer;
    }
    if (pkgbuild.pkgrel.len == 0) {
        return error.MissingPkgRel;
    }
    if (pkgbuild.arch.len == 0) {
        return error.MissingArch;
    }
}
