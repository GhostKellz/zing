const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Thread = std.Thread;
const native = @import("native.zig");
const builder = @import("builder.zig");
const packager = @import("packager.zig");

pub const BuildTarget = struct {
    name: []const u8,
    triple: []const u8,
    optimize: OptimizeMode,
    features: ?[]const []const u8 = null,

    pub const OptimizeMode = enum {
        Debug,
        ReleaseSafe,
        ReleaseFast,
        ReleaseSmall,
    };

    pub fn deinit(self: *BuildTarget, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.triple);
        if (self.features) |features| {
            for (features) |feature| allocator.free(feature);
            allocator.free(features);
        }
    }
};

pub const BuildResult = struct {
    target: BuildTarget,
    success: bool,
    output_path: ?[]const u8,
    error_message: ?[]const u8,
    build_time_ms: u64,
    package_size: u64,

    pub fn deinit(self: *BuildResult, allocator: Allocator) void {
        self.target.deinit(allocator);
        if (self.output_path) |path| allocator.free(path);
        if (self.error_message) |msg| allocator.free(msg);
    }
};

pub const MultiArchBuilder = struct {
    allocator: Allocator,
    max_parallel: u32,
    output_dir: []const u8,

    pub fn init(allocator: Allocator, max_parallel: u32) !MultiArchBuilder {
        const output_dir = try allocator.dupe(u8, "multi-arch-builds");

        // Create output directory
        std.fs.cwd().makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return MultiArchBuilder{
            .allocator = allocator,
            .max_parallel = max_parallel,
            .output_dir = output_dir,
        };
    }

    pub fn deinit(self: *MultiArchBuilder) void {
        self.allocator.free(self.output_dir);
    }

    pub fn buildForTargets(self: *MultiArchBuilder, project_dir: []const u8, targets: []const BuildTarget) ![]BuildResult {
        print("==> Starting multi-architecture build for {d} targets\n", .{targets.len});
        print("    Max parallel builds: {d}\n", .{self.max_parallel});

        var results = try self.allocator.alloc(BuildResult, targets.len);
        var threads = try self.allocator.alloc(?Thread, targets.len);
        defer self.allocator.free(threads);

        // Initialize threads array
        for (threads) |*thread| thread.* = null;

        const BuildContext = struct {
            builder: *MultiArchBuilder,
            project_dir: []const u8,
            target: BuildTarget,
            result: *BuildResult,

            fn buildTarget(ctx: *@This()) void {
                const start_time = std.time.milliTimestamp();

                ctx.result.* = BuildResult{
                    .target = ctx.target,
                    .success = false,
                    .output_path = null,
                    .error_message = null,
                    .build_time_ms = 0,
                    .package_size = 0,
                };

                // Create target-specific build directory
                const target_dir = std.fs.path.join(ctx.builder.allocator, &[_][]const u8{ ctx.builder.output_dir, ctx.target.name }) catch {
                    ctx.result.error_message = std.mem.dupe(ctx.builder.allocator, u8, "Failed to create target directory") catch null;
                    return;
                };
                defer ctx.builder.allocator.free(target_dir);

                std.fs.cwd().makeDir(target_dir) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => {
                        ctx.result.error_message = std.fmt.allocPrint(ctx.builder.allocator, "Failed to create directory: {}", .{err}) catch null;
                        return;
                    },
                };

                // Detect and build project
                const project_type = native.detectProjectType(ctx.builder.allocator, ctx.project_dir) catch {
                    ctx.result.error_message = std.mem.dupe(ctx.builder.allocator, u8, "Failed to detect project type") catch null;
                    return;
                };

                switch (project_type) {
                    .zig => {
                        var zig_proj = native.analyzeZigProject(ctx.builder.allocator, ctx.project_dir) catch {
                            ctx.result.error_message = std.mem.dupe(ctx.builder.allocator, u8, "Failed to analyze Zig project") catch null;
                            return;
                        };
                        defer zig_proj.deinit();

                        const release_mode = ctx.target.optimize != .Debug;
                        native.buildZigProject(ctx.builder.allocator, &zig_proj, ctx.target.triple, release_mode) catch |err| {
                            ctx.result.error_message = std.fmt.allocPrint(ctx.builder.allocator, "Zig build failed: {}", .{err}) catch null;
                            return;
                        };

                        // Create package
                        var native_project = native.NativeProject{ .zig = zig_proj };
                        native.createNativePackage(ctx.builder.allocator, &native_project, target_dir) catch |err| {
                            ctx.result.error_message = std.fmt.allocPrint(ctx.builder.allocator, "Package creation failed: {}", .{err}) catch null;
                            return;
                        };
                    },
                    .c, .cpp => {
                        var c_proj = native.analyzeCProject(ctx.builder.allocator, ctx.project_dir) catch {
                            ctx.result.error_message = std.mem.dupe(ctx.builder.allocator, u8, "Failed to analyze C project") catch null;
                            return;
                        };
                        defer c_proj.deinit();

                        const release_mode = ctx.target.optimize != .Debug;
                        native.buildCProject(ctx.builder.allocator, &c_proj, ctx.target.triple, release_mode) catch |err| {
                            ctx.result.error_message = std.fmt.allocPrint(ctx.builder.allocator, "C build failed: {}", .{err}) catch null;
                            return;
                        };

                        var native_project = native.NativeProject{ .c = c_proj };
                        native.createNativePackage(ctx.builder.allocator, &native_project, target_dir) catch |err| {
                            ctx.result.error_message = std.fmt.allocPrint(ctx.builder.allocator, "Package creation failed: {}", .{err}) catch null;
                            return;
                        };
                    },
                    else => {
                        ctx.result.error_message = std.mem.dupe(ctx.builder.allocator, u8, "Unsupported project type for multi-arch build") catch null;
                        return;
                    },
                }

                // Calculate build time and package size
                const end_time = std.time.milliTimestamp();
                ctx.result.build_time_ms = @as(u64, @intCast(end_time - start_time));

                // Get package size
                ctx.result.package_size = ctx.calculatePackageSize(target_dir);
                ctx.result.output_path = std.mem.dupe(ctx.builder.allocator, u8, target_dir) catch null;
                ctx.result.success = true;

                print("✅ {s}: Built in {d}ms, size: {d}KB\n", .{ ctx.target.name, ctx.result.build_time_ms, ctx.result.package_size / 1024 });
            }

            fn calculatePackageSize(ctx: *@This(), dir_path: []const u8) u64 {
                var total_size: u64 = 0;

                var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return 0;
                defer dir.close();

                var walker = dir.walk(ctx.builder.allocator) catch return 0;
                defer walker.deinit();

                while (walker.next() catch null) |entry| {
                    if (entry.kind == .file) {
                        const stat = dir.statFile(entry.path) catch continue;
                        total_size += stat.size;
                    }
                }

                return total_size;
            }
        };

        var contexts = try self.allocator.alloc(BuildContext, targets.len);
        defer self.allocator.free(contexts);

        // Start builds with concurrency limit
        var active_builds: u32 = 0;
        var completed: u32 = 0;

        while (completed < targets.len) {
            // Start new builds up to the limit
            while (active_builds < self.max_parallel and completed + active_builds < targets.len) {
                const idx = completed + active_builds;

                contexts[idx] = BuildContext{
                    .builder = self,
                    .project_dir = project_dir,
                    .target = targets[idx],
                    .result = &results[idx],
                };

                print("==> Starting build for {s} ({s})\n", .{ targets[idx].name, targets[idx].triple });

                threads[idx] = Thread.spawn(.{}, BuildContext.buildTarget, .{&contexts[idx]}) catch {
                    results[idx] = BuildResult{
                        .target = targets[idx],
                        .success = false,
                        .output_path = null,
                        .error_message = std.mem.dupe(self.allocator, u8, "Failed to start build thread") catch null,
                        .build_time_ms = 0,
                        .package_size = 0,
                    };
                    completed += 1;
                    continue;
                };

                active_builds += 1;
            }

            // Wait for at least one build to complete
            if (active_builds > 0) {
                // Check for completed threads
                for (threads, 0..) |*thread, i| {
                    if (thread.*) |t| {
                        if (i < completed + active_builds) {
                            t.join();
                            thread.* = null;
                            active_builds -= 1;
                            completed += 1;
                            break;
                        }
                    }
                }

                // Small delay to prevent busy waiting
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }

        // Wait for any remaining threads
        for (threads) |thread| {
            if (thread) |t| {
                t.join();
            }
        }

        return results;
    }

    pub fn generateBuildReport(self: *MultiArchBuilder, results: []const BuildResult) !void {
        print("\n==> Multi-Architecture Build Report\n", .{});
        print("====================================\n", .{});

        var successful: u32 = 0;
        var failed: u32 = 0;
        var total_time: u64 = 0;
        var total_size: u64 = 0;

        for (results) |result| {
            if (result.success) {
                successful += 1;
                total_time += result.build_time_ms;
                total_size += result.package_size;
                print("✅ {s:<20} | {s:<25} | {d:>6}ms | {d:>8}KB\n", .{
                    result.target.name,
                    result.target.triple,
                    result.build_time_ms,
                    result.package_size / 1024,
                });
            } else {
                failed += 1;
                const error_msg = result.error_message orelse "Unknown error";
                print("❌ {s:<20} | {s:<25} | FAILED: {s}\n", .{
                    result.target.name,
                    result.target.triple,
                    error_msg,
                });
            }
        }

        print("------------------------------------\n", .{});
        print("Summary: {d} successful, {d} failed\n", .{ successful, failed });
        print("Total build time: {d}ms\n", .{total_time});
        print("Total package size: {d}MB\n", .{total_size / 1024 / 1024});
        print("Average build time: {d}ms\n", .{if (successful > 0) total_time / successful else 0});

        if (successful > 0) {
            print("Packages available in: {s}/\n", .{self.output_dir});
        }
    }
};

// Predefined target sets
pub const CommonTargets = struct {
    pub const desktop = [_]BuildTarget{
        BuildTarget{ .name = "linux-x64", .triple = "x86_64-linux-gnu", .optimize = .ReleaseFast },
        BuildTarget{ .name = "windows-x64", .triple = "x86_64-windows-gnu", .optimize = .ReleaseFast },
        BuildTarget{ .name = "macos-x64", .triple = "x86_64-macos", .optimize = .ReleaseFast },
    };

    pub const embedded = [_]BuildTarget{
        BuildTarget{ .name = "arm64-linux", .triple = "aarch64-linux-gnu", .optimize = .ReleaseSmall },
        BuildTarget{ .name = "arm32-linux", .triple = "arm-linux-gnueabihf", .optimize = .ReleaseSmall },
        BuildTarget{ .name = "riscv64-linux", .triple = "riscv64-linux-gnu", .optimize = .ReleaseSmall },
    };

    pub const web = [_]BuildTarget{
        BuildTarget{ .name = "wasm32-wasi", .triple = "wasm32-wasi", .optimize = .ReleaseSmall },
        BuildTarget{ .name = "wasm32-freestanding", .triple = "wasm32-freestanding", .optimize = .ReleaseSmall },
    };

    pub const all_platforms = desktop ++ embedded ++ web;
};

pub fn createBuildMatrix(allocator: Allocator, targets: []const BuildTarget, optimize_modes: []const BuildTarget.OptimizeMode) ![]BuildTarget {
    var matrix = ArrayList(BuildTarget).init(allocator);
    defer matrix.deinit();

    for (targets) |target| {
        for (optimize_modes) |mode| {
            const name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ target.name, @tagName(mode) });

            try matrix.append(BuildTarget{
                .name = name,
                .triple = try allocator.dupe(u8, target.triple),
                .optimize = mode,
                .features = null,
            });
        }
    }

    return try matrix.toOwnedSlice();
}
