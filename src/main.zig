const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = std.Io.Dir;
const File = std.Io.File;
const parser = @import("parser.zig");
const builder = @import("builder.zig");
const native = @import("native.zig");

const Command = enum {
    help,
    version,
    init,
    build,
    package,
    clean,
    detect,
    compile,
    cross_compile,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        showHelp();
        return;
    }

    const command = parseCommand(args[1]) catch {
        print("Unknown command: {s}\n", .{args[1]});
        print("Run 'zing help' for available commands\n", .{});
        return;
    };

    switch (command) {
        .help => showHelp(),
        .version => showVersion(),
        .init => try initWorkspace(io),
        .build => {
            const path = if (args.len > 2) args[2] else "PKGBUILD";
            try buildFromPkgBuild(allocator, io, path);
        },
        .package => {
            const path = if (args.len > 2) args[2] else "PKGBUILD";
            try packageFromPkgBuild(allocator, io, path);
        },
        .clean => try cleanBuild(io),
        .detect => try detectProjectType(allocator, io, "."),
        .compile => {
            const release = args.len > 2 and std.mem.eql(u8, args[2], "--release");
            try compileNativeProject(allocator, io, ".", null, release);
        },
        .cross_compile => {
            if (args.len < 3) {
                print("Usage: zing cross <target> [--release]\n", .{});
                return;
            }
            const target = args[2];
            const release = args.len > 3 and std.mem.eql(u8, args[3], "--release");
            try compileNativeProject(allocator, io, ".", target, release);
        },
    }
}

fn parseCommand(arg: []const u8) !Command {
    const commands = [_]struct { []const u8, Command }{
        .{ "help", .help },
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "version", .version },
        .{ "--version", .version },
        .{ "-v", .version },
        .{ "init", .init },
        .{ "build", .build },
        .{ "package", .package },
        .{ "clean", .clean },
        .{ "detect", .detect },
        .{ "compile", .compile },
        .{ "cross", .cross_compile },
    };

    for (commands) |cmd| {
        if (std.mem.eql(u8, arg, cmd[0])) {
            return cmd[1];
        }
    }
    return error.UnknownCommand;
}

fn showHelp() void {
    print(
        \\Zing - Next-Generation Build & Packaging Engine for Arch Linux
        \\
        \\USAGE:
        \\    zing <COMMAND> [OPTIONS]
        \\
        \\PKGBUILD COMMANDS:
        \\    init                 Initialize a new build workspace
        \\    build [PKGBUILD]     Build a package from PKGBUILD (default: ./PKGBUILD)
        \\    package [PKGBUILD]   Build and package from PKGBUILD
        \\    clean                Clean build cache and artifacts
        \\
        \\NATIVE COMPILATION:
        \\    detect               Auto-detect project type (Zig/C/C++)
        \\    compile [--release]  Compile native project with Zig compiler
        \\    cross <target> [--release]  Cross-compile for specific target
        \\
        \\GENERAL:
        \\    version              Show version information
        \\    help                 Show this help message
        \\
        \\For more information, visit: https://github.com/ghostkellz/zing
        \\
    , .{});
}

fn showVersion() void {
    print(
        \\Zing v0.1.0 - Next-Generation Build & Packaging Engine
        \\Built with Zig 0.16.0-dev.2193+fc517bd01
        \\Copyright (c) 2024-2025 GhostKellz
        \\Licensed under MIT License
        \\
    , .{});
}

fn initWorkspace(io: Io) !void {
    print("Initializing zing workspace...\n", .{});

    const pkgbuild_content =
        \\# Maintainer: Your Name <your.email@example.com>
        \\pkgname=my-package
        \\pkgver=1.0.0
        \\pkgrel=1
        \\pkgdesc="A package built with zing"
        \\arch=('x86_64')
        \\url="https://github.com/username/my-package"
        \\license=('MIT')
        \\depends=()
        \\makedepends=('gcc')
        \\source=("my-package-${pkgver}.tar.gz")
        \\sha256sums('SKIP')
        \\
        \\prepare() {
        \\    echo "Preparing build environment..."
        \\}
        \\
        \\build() {
        \\    echo "Building package..."
        \\    # Add your build commands here
        \\}
        \\
        \\check() {
        \\    echo "Running tests..."
        \\    # Add your test commands here
        \\}
        \\
        \\package() {
        \\    echo "Installing package..."
        \\    # Add your installation commands here
        \\}
    ;

    const file = Dir.cwd().createFile(io, "PKGBUILD", .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            print("PKGBUILD already exists, skipping...\n", .{});
            return;
        },
        else => return err,
    };
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = File.Writer.init(file, io, &buffer);
    try writer.interface.print("{s}", .{pkgbuild_content});
    try writer.interface.flush();

    print("Created example PKGBUILD\n", .{});
    print("Edit the PKGBUILD file and run 'zing build' to get started!\n", .{});
}

fn readFileAlloc(allocator: Allocator, io: Io, file: File) ![]u8 {
    const stat = try file.stat(io);
    const size: usize = @intCast(@min(stat.size, 1024 * 1024));
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    var read_buffer: [8192]u8 = undefined;
    var reader = File.Reader.init(file, io, &read_buffer);

    var total_read: usize = 0;
    while (total_read < size) {
        const bytes_read = reader.interface.readSliceShort(buffer[total_read..]) catch {
            break;
        };
        if (bytes_read == 0) break;
        total_read += bytes_read;
    }
    return buffer[0..total_read];
}

fn runBuildPipeline(allocator: Allocator, io: Io, path: []const u8, do_package: bool) !void {
    print("Building from: {s}\n", .{path});

    const file = Dir.cwd().openFile(io, path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            print("PKGBUILD file not found: {s}\n", .{path});
            print("Run 'zing init' to create an example PKGBUILD\n", .{});
        }
        return err;
    };
    defer file.close(io);

    const content = try readFileAlloc(allocator, io, file);
    defer allocator.free(content);

    var pkgbuild = try parser.parsePkgBuild(allocator, content);
    var owns_pkgbuild = true;
    defer if (owns_pkgbuild) pkgbuild.deinit();

    parser.validatePkgBuild(&pkgbuild) catch |err| {
        print("Invalid PKGBUILD: {}\n", .{err});
        return err;
    };

    var ctx = builder.BuildContext.init(allocator, io, pkgbuild, content) catch |err| {
        print("Failed to initialize build context: {}\n", .{err});
        return err;
    };
    owns_pkgbuild = false;
    defer ctx.deinit();

    builder.prepareBuild(&ctx) catch |err| {
        print("Build preparation failed: {}\n", .{err});
        return err;
    };

    builder.buildPackage(&ctx) catch |err| {
        print("Build step failed: {}\n", .{err});
        return err;
    };

    if (do_package) {
        builder.packageFiles(&ctx) catch |err| {
            print("Packaging failed: {}\n", .{err});
            return err;
        };
    } else {
        print("Build completed\n", .{});
    }
}

fn buildFromPkgBuild(allocator: Allocator, io: Io, path: []const u8) !void {
    try runBuildPipeline(allocator, io, path, false);
}

fn packageFromPkgBuild(allocator: Allocator, io: Io, path: []const u8) !void {
    try runBuildPipeline(allocator, io, path, true);
}

fn cleanBuild(io: Io) !void {
    print("==> Cleaning build artifacts\n", .{});

    Dir.cwd().deleteTree(io, "build") catch {};
    Dir.cwd().deleteTree(io, "src") catch {};
    Dir.cwd().deleteTree(io, "pkg") catch {};

    print("==> Clean completed\n", .{});
}

fn detectProjectType(allocator: Allocator, io: Io, project_dir: []const u8) !void {
    print("Detecting project type in: {s}\n", .{project_dir});

    const project_type = native.detectProjectType(allocator, io, project_dir) catch |err| {
        print("Failed to detect project type: {}\n", .{err});
        return;
    };

    switch (project_type) {
        .zig => {
            print("Detected: Zig Project\n", .{});
            var zig_project = native.analyzeZigProject(allocator, io, project_dir) catch |err| {
                print("Failed to analyze Zig project: {}\n", .{err});
                return;
            };
            defer zig_project.deinit();

            print("   Name: {s}\n", .{zig_project.name});
            print("   Version: {s}\n", .{zig_project.version});
        },
        .c => {
            print("Detected: C Project\n", .{});
            var c_project = native.analyzeCProject(allocator, io, project_dir) catch |err| {
                print("Failed to analyze C project: {}\n", .{err});
                return;
            };
            defer c_project.deinit();

            print("   Sources: {d} files\n", .{c_project.sources.len});
            print("   Headers: {d} files\n", .{c_project.headers.len});
        },
        .cpp => {
            print("Detected: C++ Project\n", .{});
            var cpp_project = native.analyzeCProject(allocator, io, project_dir) catch |err| {
                print("Failed to analyze C++ project: {}\n", .{err});
                return;
            };
            defer cpp_project.deinit();

            print("   Sources: {d} files\n", .{cpp_project.sources.len});
            print("   Headers: {d} files\n", .{cpp_project.headers.len});
        },
        .mixed => {
            print("Detected: Mixed Project (Zig + C/C++)\n", .{});
            print("   Mixed projects not yet fully supported in detect mode\n", .{});
        },
        .unknown => {
            print("Unknown project type\n", .{});
            print("Supported types: Zig (.zig files), C (.c files), C++ (.cpp files)\n", .{});
        },
    }
}

fn compileNativeProject(allocator: Allocator, io: Io, project_dir: []const u8, target: ?[]const u8, release_mode: bool) !void {
    const mode_str = if (release_mode) "release" else "debug";

    if (target) |t| {
        print("Cross-compiling for: {s}\n", .{t});
    } else {
        print("Compiling native project ({s} mode)\n", .{mode_str});
    }

    const project_type = native.detectProjectType(allocator, io, project_dir) catch |err| {
        print("Failed to detect project type: {}\n", .{err});
        return;
    };

    switch (project_type) {
        .zig => {
            print("Detected: Zig Project\n", .{});
            var zig_project = native.analyzeZigProject(allocator, io, project_dir) catch |err| {
                print("Failed to analyze Zig project: {}\n", .{err});
                return;
            };
            defer zig_project.deinit();

            print("==> Building Zig project: {s} v{s}\n", .{ zig_project.name, zig_project.version });

            native.buildZigProject(allocator, &zig_project, target, release_mode) catch |err| {
                print("Build failed: {}\n", .{err});
                return;
            };
        },
        .c => {
            print("Detected: C Project\n", .{});
            var c_project = native.analyzeCProject(allocator, io, project_dir) catch |err| {
                print("Failed to analyze C project: {}\n", .{err});
                return;
            };
            defer c_project.deinit();

            print("==> Building C project: {s} v{s}\n", .{ c_project.name, c_project.version });

            native.buildCProject(allocator, &c_project, target, release_mode) catch |err| {
                print("Build failed: {}\n", .{err});
                return;
            };
        },
        .cpp => {
            print("Detected: C++ Project\n", .{});
            var cpp_project = native.analyzeCProject(allocator, io, project_dir) catch |err| {
                print("Failed to analyze C++ project: {}\n", .{err});
                return;
            };
            defer cpp_project.deinit();

            print("==> Building C++ project: {s} v{s}\n", .{ cpp_project.name, cpp_project.version });

            native.buildCProject(allocator, &cpp_project, target, release_mode) catch |err| {
                print("Build failed: {}\n", .{err});
                return;
            };
        },
        .mixed => {
            print("Detected: Mixed Project\n", .{});
            print("Mixed project compilation not yet implemented\n", .{});
        },
        .unknown => {
            print("Cannot compile unknown project type\n", .{});
            print("Run 'zing detect' to see what was found\n", .{});
            return;
        },
    }

    print("Native compilation completed ({s} mode)!\n", .{mode_str});
}
