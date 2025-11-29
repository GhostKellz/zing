const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const ZmkConfig = struct {
    package: PackageConfig,
    build: ?BuildConfig = null,
    dependencies: ?DependencyConfig = null,
    targets: ?[]TargetConfig = null,
    allocator: Allocator,
};

pub const PackageConfig = struct {
    name: []const u8,
    version: []const u8,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    license: []const []const u8,
    arch: []const []const u8,
    maintainer: ?[]const u8 = null,
    conflicts: ?[]const []const u8 = null,
    provides: ?[]const []const u8 = null,
    replaces: ?[]const []const u8 = null,
};

pub const BuildConfig = struct {
    type: BuildType = .auto,
    sources: ?[]const []const u8 = null,
    checksums: ?[]const []const u8 = null,
    prepare_script: ?[]const u8 = null,
    build_script: ?[]const u8 = null,
    check_script: ?[]const u8 = null,
    package_script: ?[]const u8 = null,
    build_dir: ?[]const u8 = null,
    install_dir: ?[]const u8 = null,

    pub const BuildType = enum {
        auto,
        zig,
        c,
        cpp,
        make,
        cmake,
        meson,
        custom,
    };
};

pub const DependencyConfig = struct {
    runtime: ?[]const []const u8 = null,
    build: ?[]const []const u8 = null,
    check: ?[]const []const u8 = null,
    optional: ?[]const []const u8 = null,
    aur: ?[]const []const u8 = null,
};

pub const TargetConfig = struct {
    name: []const u8,
    triple: []const u8,
    features: ?[]const []const u8 = null,
    optimize: OptimizeMode = .ReleaseFast,

    pub const OptimizeMode = enum {
        Debug,
        ReleaseSafe,
        ReleaseFast,
        ReleaseSmall,
    };
};

pub fn deinitZmkConfig(self: *ZmkConfig) void {
    self.allocator.free(self.package.name);
    self.allocator.free(self.package.version);
    if (self.package.description) |desc| self.allocator.free(desc);
    if (self.package.url) |url| self.allocator.free(url);
    if (self.package.maintainer) |maint| self.allocator.free(maint);

    for (self.package.license) |lic| self.allocator.free(lic);
    self.allocator.free(self.package.license);

    for (self.package.arch) |arch| self.allocator.free(arch);
    self.allocator.free(self.package.arch);

    if (self.package.conflicts) |conflicts| {
        for (conflicts) |conflict| self.allocator.free(conflict);
        self.allocator.free(conflicts);
    }

    if (self.build) |*build| {
        if (build.sources) |sources| {
            for (sources) |src| self.allocator.free(src);
            self.allocator.free(sources);
        }
        if (build.checksums) |checksums| {
            for (checksums) |sum| self.allocator.free(sum);
            self.allocator.free(checksums);
        }
        if (build.prepare_script) |script| self.allocator.free(script);
        if (build.build_script) |script| self.allocator.free(script);
        if (build.check_script) |script| self.allocator.free(script);
        if (build.package_script) |script| self.allocator.free(script);
        if (build.build_dir) |dir| self.allocator.free(dir);
        if (build.install_dir) |dir| self.allocator.free(dir);
    }

    if (self.dependencies) |*deps| {
        if (deps.runtime) |runtime| {
            for (runtime) |dep| self.allocator.free(dep);
            self.allocator.free(runtime);
        }
        if (deps.build) |build| {
            for (build) |dep| self.allocator.free(dep);
            self.allocator.free(build);
        }
        if (deps.aur) |aur| {
            for (aur) |dep| self.allocator.free(dep);
            self.allocator.free(aur);
        }
    }

    if (self.targets) |targets| {
        for (targets) |*target| {
            self.allocator.free(target.name);
            self.allocator.free(target.triple);
            if (target.features) |features| {
                for (features) |feature| self.allocator.free(feature);
                self.allocator.free(features);
            }
        }
        self.allocator.free(targets);
    }
}

pub fn parseZmkToml(allocator: Allocator, content: []const u8) !ZmkConfig {
    print("==> Parsing zmk.toml configuration...\n", .{});

    // For now, implement a simple TOML-like parser
    // In production, use a proper TOML library
    var config = ZmkConfig{
        .package = undefined,
        .allocator = allocator,
    };

    // Initialize with defaults
    config.package = ZmkConfig.PackageConfig{
        .name = try allocator.dupe(u8, "unnamed"),
        .version = try allocator.dupe(u8, "1.0.0"),
        .license = &[_][]const u8{},
        .arch = &[_][]const u8{},
    };

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_section: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Section headers
        if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
            current_section = try allocator.dupe(u8, trimmed[1 .. trimmed.len - 1]);
            continue;
        }

        // Key-value pairs
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            if (current_section == null or std.mem.eql(u8, current_section.?, "package")) {
                try parsePackageField(&config.package, allocator, key, value);
            } else if (std.mem.eql(u8, current_section.?, "build")) {
                if (config.build == null) {
                    config.build = ZmkConfig.BuildConfig{};
                }
                try parseBuildField(&config.build.?, allocator, key, value);
            } else if (std.mem.eql(u8, current_section.?, "dependencies")) {
                if (config.dependencies == null) {
                    config.dependencies = ZmkConfig.DependencyConfig{};
                }
                try parseDependencyField(&config.dependencies.?, allocator, key, value);
            }
        }
    }

    return config;
}

fn parsePackageField(package: *ZmkConfig.PackageConfig, allocator: Allocator, key: []const u8, value: []const u8) !void {
    const clean_value = std.mem.trim(u8, value, "\"' \t");

    if (std.mem.eql(u8, key, "name")) {
        allocator.free(package.name);
        package.name = try allocator.dupe(u8, clean_value);
    } else if (std.mem.eql(u8, key, "version")) {
        allocator.free(package.version);
        package.version = try allocator.dupe(u8, clean_value);
    } else if (std.mem.eql(u8, key, "description")) {
        if (package.description) |desc| allocator.free(desc);
        package.description = try allocator.dupe(u8, clean_value);
    } else if (std.mem.eql(u8, key, "url")) {
        if (package.url) |url| allocator.free(url);
        package.url = try allocator.dupe(u8, clean_value);
    } else if (std.mem.eql(u8, key, "license")) {
        package.license = try parseStringArray(allocator, clean_value);
    } else if (std.mem.eql(u8, key, "arch")) {
        package.arch = try parseStringArray(allocator, clean_value);
    }
}

fn parseBuildField(build: *ZmkConfig.BuildConfig, allocator: Allocator, key: []const u8, value: []const u8) !void {
    const clean_value = std.mem.trim(u8, value, "\"' \t");

    if (std.mem.eql(u8, key, "type")) {
        build.type = std.meta.stringToEnum(ZmkConfig.BuildConfig.BuildType, clean_value) orelse .auto;
    } else if (std.mem.eql(u8, key, "sources")) {
        build.sources = try parseStringArray(allocator, clean_value);
    } else if (std.mem.eql(u8, key, "checksums")) {
        build.checksums = try parseStringArray(allocator, clean_value);
    } else if (std.mem.eql(u8, key, "prepare_script")) {
        if (build.prepare_script) |script| allocator.free(script);
        build.prepare_script = try allocator.dupe(u8, clean_value);
    } else if (std.mem.eql(u8, key, "build_script")) {
        if (build.build_script) |script| allocator.free(script);
        build.build_script = try allocator.dupe(u8, clean_value);
    }
}

fn parseDependencyField(deps: *ZmkConfig.DependencyConfig, allocator: Allocator, key: []const u8, value: []const u8) !void {
    const clean_value = std.mem.trim(u8, value, "\"' \t");

    if (std.mem.eql(u8, key, "runtime")) {
        deps.runtime = try parseStringArray(allocator, clean_value);
    } else if (std.mem.eql(u8, key, "build")) {
        deps.build = try parseStringArray(allocator, clean_value);
    } else if (std.mem.eql(u8, key, "aur")) {
        deps.aur = try parseStringArray(allocator, clean_value);
    }
}

fn parseStringArray(allocator: Allocator, value: []const u8) ![][]const u8 {
    if (value.len == 0) return &[_][]const u8{};

    // Handle array format: ["item1", "item2"] or simple: "item1, item2"
    var clean_value = value;
    if (value[0] == '[' and value[value.len - 1] == ']') {
        clean_value = value[1 .. value.len - 1];
    }

    var result = ArrayList([]const u8).init(allocator);
    defer result.deinit();

    var items = std.mem.splitScalar(u8, clean_value, ',');
    while (items.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t\"'");
        if (trimmed.len > 0) {
            try result.append(try allocator.dupe(u8, trimmed));
        }
    }

    return try result.toOwnedSlice();
}

pub fn generatePkgBuildFromZmk(allocator: Allocator, config: *const ZmkConfig) ![]const u8 {
    var content = ArrayList(u8).init(allocator);
    defer content.deinit();

    const writer = content.writer();

    // Header
    try writer.writeAll("# Generated by zmake from zmk.toml\n");
    if (config.package.maintainer) |maintainer| {
        try writer.print("# Maintainer: {s}\n", .{maintainer});
    }
    try writer.writeAll("\n");

    // Package info
    try writer.print("pkgname={s}\n", .{config.package.name});
    try writer.print("pkgver={s}\n", .{config.package.version});
    try writer.writeAll("pkgrel=1\n");

    if (config.package.description) |desc| {
        try writer.print("pkgdesc=\"{s}\"\n", .{desc});
    }

    if (config.package.url) |url| {
        try writer.print("url=\"{s}\"\n", .{url});
    }

    // Architecture
    try writer.writeAll("arch=(");
    for (config.package.arch, 0..) |arch, i| {
        if (i > 0) try writer.writeAll(" ");
        try writer.print("'{s}'", .{arch});
    }
    try writer.writeAll(")\n");

    // License
    try writer.writeAll("license=(");
    for (config.package.license, 0..) |license, i| {
        if (i > 0) try writer.writeAll(" ");
        try writer.print("'{s}'", .{license});
    }
    try writer.writeAll(")\n");

    // Dependencies
    if (config.dependencies) |deps| {
        if (deps.runtime) |runtime| {
            try writer.writeAll("depends=(");
            for (runtime, 0..) |dep, i| {
                if (i > 0) try writer.writeAll(" ");
                try writer.print("'{s}'", .{dep});
            }
            try writer.writeAll(")\n");
        }

        if (deps.build) |build| {
            try writer.writeAll("makedepends=(");
            for (build, 0..) |dep, i| {
                if (i > 0) try writer.writeAll(" ");
                try writer.print("'{s}'", .{dep});
            }
            try writer.writeAll(")\n");
        }
    }

    // Sources
    if (config.build) |build| {
        if (build.sources) |sources| {
            try writer.writeAll("source=(");
            for (sources, 0..) |source, i| {
                if (i > 0) try writer.writeAll(" ");
                try writer.print("'{s}'", .{source});
            }
            try writer.writeAll(")\n");
        }

        if (build.checksums) |checksums| {
            try writer.writeAll("sha256sums=(");
            for (checksums, 0..) |checksum, i| {
                if (i > 0) try writer.writeAll(" ");
                try writer.print("'{s}'", .{checksum});
            }
            try writer.writeAll(")\n");
        }
    }

    try writer.writeAll("\n");

    // Build functions based on type
    if (config.build) |build| {
        switch (build.type) {
            .zig => {
                try writer.writeAll("build() {\n");
                try writer.writeAll("  cd \"$srcdir\"\n");
                try writer.writeAll("  zig build -Drelease-fast\n");
                try writer.writeAll("}\n\n");

                try writer.writeAll("package() {\n");
                try writer.writeAll("  cd \"$srcdir\"\n");
                try writer.print("  install -Dm755 zig-out/bin/{s} \"$pkgdir/usr/bin/{s}\"\n", .{ config.package.name, config.package.name });
                try writer.writeAll("}\n");
            },
            .c, .cpp => {
                try writer.writeAll("build() {\n");
                try writer.writeAll("  cd \"$srcdir\"\n");
                if (build.build_script) |script| {
                    try writer.print("  {s}\n", .{script});
                } else {
                    try writer.writeAll("  zig cc -O3 *.c -o \"$pkgname\"\n");
                }
                try writer.writeAll("}\n\n");

                try writer.writeAll("package() {\n");
                try writer.writeAll("  cd \"$srcdir\"\n");
                try writer.print("  install -Dm755 {s} \"$pkgdir/usr/bin/{s}\"\n", .{ config.package.name, config.package.name });
                try writer.writeAll("}\n");
            },
            else => {
                if (build.prepare_script) |script| {
                    try writer.writeAll("prepare() {\n");
                    try writer.print("  {s}\n", .{script});
                    try writer.writeAll("}\n\n");
                }

                if (build.build_script) |script| {
                    try writer.writeAll("build() {\n");
                    try writer.writeAll("  cd \"$srcdir\"\n");
                    try writer.print("  {s}\n", .{script});
                    try writer.writeAll("}\n\n");
                }

                if (build.package_script) |script| {
                    try writer.writeAll("package() {\n");
                    try writer.writeAll("  cd \"$srcdir\"\n");
                    try writer.print("  {s}\n", .{script});
                    try writer.writeAll("}\n");
                }
            },
        }
    }

    return try content.toOwnedSlice();
}
