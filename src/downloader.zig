const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const DownloadResult = struct {
    success: bool,
    path: []const u8,
    error_msg: ?[]const u8,

    pub fn deinit(self: *DownloadResult, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.error_msg) |msg| allocator.free(msg);
    }
};

pub fn downloadFile(allocator: Allocator, url: []const u8, dest_path: []const u8) !DownloadResult {
    print("==> Downloading: {s}\n", .{url});

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Invalid URL: {}", .{err});
        return DownloadResult{
            .success = false,
            .path = try allocator.dupe(u8, dest_path),
            .error_msg = error_msg,
        };
    };

    var request = client.open(.GET, uri, .{
        .server_header_buffer = try allocator.alloc(u8, 8192),
    }) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open connection: {}", .{err});
        return DownloadResult{
            .success = false,
            .path = try allocator.dupe(u8, dest_path),
            .error_msg = error_msg,
        };
    };
    defer request.deinit();

    request.send() catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to send request: {}", .{err});
        return DownloadResult{
            .success = false,
            .path = try allocator.dupe(u8, dest_path),
            .error_msg = error_msg,
        };
    };

    request.wait() catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Request failed: {}", .{err});
        return DownloadResult{
            .success = false,
            .path = try allocator.dupe(u8, dest_path),
            .error_msg = error_msg,
        };
    };

    if (request.response.status != .ok) {
        const error_msg = try std.fmt.allocPrint(allocator, "HTTP error: {}", .{request.response.status});
        return DownloadResult{
            .success = false,
            .path = try allocator.dupe(u8, dest_path),
            .error_msg = error_msg,
        };
    }

    // Create destination file
    var file = std.fs.cwd().createFile(dest_path, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to create file: {}", .{err});
        return DownloadResult{
            .success = false,
            .path = try allocator.dupe(u8, dest_path),
            .error_msg = error_msg,
        };
    };
    defer file.close();

    // Read and write in chunks with progress
    var total_bytes: u64 = 0;
    var buffer: [8192]u8 = undefined;

    while (true) {
        const bytes_read = request.readAll(&buffer) catch |err| {
            const error_msg = try std.fmt.allocPrint(allocator, "Failed to read response: {}", .{err});
            return DownloadResult{
                .success = false,
                .path = try allocator.dupe(u8, dest_path),
                .error_msg = error_msg,
            };
        };

        if (bytes_read == 0) break;

        file.writeAll(buffer[0..bytes_read]) catch |err| {
            const error_msg = try std.fmt.allocPrint(allocator, "Failed to write file: {}", .{err});
            return DownloadResult{
                .success = false,
                .path = try allocator.dupe(u8, dest_path),
                .error_msg = error_msg,
            };
        };

        total_bytes += bytes_read;
        if (total_bytes % (64 * 1024) == 0) {
            print("    Downloaded: {d} KB\r", .{total_bytes / 1024});
        }
    }

    print("    Downloaded: {d} KB ✓\n", .{total_bytes / 1024});

    return DownloadResult{
        .success = true,
        .path = try allocator.dupe(u8, dest_path),
        .error_msg = null,
    };
}

pub fn downloadParallel(allocator: Allocator, urls: []const []const u8, dest_dir: []const u8) ![]DownloadResult {
    var results = try allocator.alloc(DownloadResult, urls.len);
    var threads = try allocator.alloc(std.Thread, urls.len);
    defer allocator.free(threads);

    const DownloadContext = struct {
        allocator: Allocator,
        url: []const u8,
        dest_path: []const u8,
        result: *DownloadResult,
    };

    var contexts = try allocator.alloc(DownloadContext, urls.len);
    defer allocator.free(contexts);

    // Start all downloads
    for (urls, 0..) |url, i| {
        const filename = std.fs.path.basename(url);
        const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_dir, filename });

        contexts[i] = DownloadContext{
            .allocator = allocator,
            .url = url,
            .dest_path = dest_path,
            .result = &results[i],
        };

        const downloadThread = struct {
            fn run(ctx: *DownloadContext) void {
                ctx.result.* = downloadFile(ctx.allocator, ctx.url, ctx.dest_path) catch |err| {
                    const error_msg = std.fmt.allocPrint(ctx.allocator, "Download failed: {}", .{err}) catch "Unknown error";
                    ctx.result.* = DownloadResult{
                        .success = false,
                        .path = std.mem.dupe(ctx.allocator, u8, ctx.dest_path) catch "",
                        .error_msg = error_msg,
                    };
                };
            }
        }.run;

        threads[i] = try std.Thread.spawn(.{}, downloadThread, .{&contexts[i]});
    }

    // Wait for all downloads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Clean up dest_paths
    for (contexts) |ctx| {
        allocator.free(ctx.dest_path);
    }

    return results;
}

pub fn verifySha256(allocator: Allocator, file_path: []const u8, expected_hash: []const u8) !bool {
    _ = allocator;
    if (std.mem.eql(u8, expected_hash, "SKIP")) return true;

    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [8192]u8 = undefined;

    while (true) {
        const bytes_read = file.readAll(&buffer) catch break;
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }

    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);

    var hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hash_hex, "{}", .{std.fmt.fmtSliceHexLower(&hash_bytes)}) catch return false;

    return std.mem.eql(u8, &hash_hex, expected_hash);
}
