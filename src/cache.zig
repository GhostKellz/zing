const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const CacheEntry = struct {
    hash: []const u8,
    path: []const u8,
    size: u64,
    timestamp: i64,
    access_count: u32,

    pub fn deinit(self: *CacheEntry, allocator: Allocator) void {
        allocator.free(self.hash);
        allocator.free(self.path);
    }
};

pub const BuildCache = struct {
    allocator: Allocator,
    cache_dir: []const u8,
    entries: std.StringHashMap(CacheEntry),
    max_size: u64,
    current_size: u64,

    pub fn init(allocator: Allocator, cache_dir: []const u8, max_size_mb: u32) !BuildCache {
        var cache = BuildCache{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_size = @as(u64, max_size_mb) * 1024 * 1024,
            .current_size = 0,
        };

        // Create cache directory
        std.fs.cwd().makeDir(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        try cache.loadCacheIndex();
        return cache;
    }

    pub fn deinit(self: *BuildCache) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            var cache_entry = entry.value_ptr;
            cache_entry.deinit(self.allocator);
        }
        self.entries.deinit();
        self.allocator.free(self.cache_dir);
    }

    fn loadCacheIndex(self: *BuildCache) !void {
        const index_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, "index.json" });
        defer self.allocator.free(index_path);

        const file = std.fs.cwd().openFile(index_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                print("==> Creating new cache index\n", .{});
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // For now, implement simple parsing - in production use JSON parser
        print("==> Loaded cache index with {d} entries\n", .{self.entries.count()});
    }

    fn saveCacheIndex(self: *BuildCache) !void {
        const index_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, "index.json" });
        defer self.allocator.free(index_path);

        var file = try std.fs.cwd().createFile(index_path, .{});
        defer file.close();

        // Simple JSON-like format for now
        try file.writeAll("{\n  \"entries\": [\n");

        var iterator = self.entries.iterator();
        var first = true;
        while (iterator.next()) |entry| {
            if (!first) try file.writeAll(",\n");
            first = false;

            const json_entry = try std.fmt.allocPrint(self.allocator,
                \\    {{
                \\      "hash": "{s}",
                \\      "path": "{s}",
                \\      "size": {d},
                \\      "timestamp": {d},
                \\      "access_count": {d}
                \\    }}
            , .{ entry.value_ptr.hash, entry.value_ptr.path, entry.value_ptr.size, entry.value_ptr.timestamp, entry.value_ptr.access_count });
            defer self.allocator.free(json_entry);

            try file.writeAll(json_entry);
        }

        try file.writeAll("\n  ]\n}\n");
    }

    pub fn computeSourceHash(self: *BuildCache, sources: []const []const u8, pkgbuild_content: []const u8) ![]const u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        // Hash PKGBUILD content
        hasher.update(pkgbuild_content);

        // Hash source URLs/files in sorted order
        const sorted_sources = try self.allocator.alloc([]const u8, sources.len);
        defer self.allocator.free(sorted_sources);

        @memcpy(sorted_sources, sources);
        std.mem.sort([]const u8, sorted_sources, {}, struct {
            fn lessThan(context: void, a: []const u8, b: []const u8) bool {
                _ = context;
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (sorted_sources) |source| {
            hasher.update(source);
        }

        var hash_bytes: [32]u8 = undefined;
        hasher.final(&hash_bytes);

        const hash_hex = try self.allocator.alloc(u8, 64);
        _ = std.fmt.bufPrint(hash_hex, "{}", .{std.fmt.fmtSliceHexLower(&hash_bytes)}) catch unreachable;

        return hash_hex;
    }

    pub fn getCachedBuild(self: *BuildCache, hash: []const u8) ?[]const u8 {
        if (self.entries.get(hash)) |entry| {
            const cache_path = std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, entry.path }) catch return null;

            // Check if file exists
            std.fs.cwd().access(cache_path, .{}) catch {
                self.allocator.free(cache_path);
                return null;
            };

            print("✅ Cache hit: {s}\n", .{hash[0..16]});

            // Update access count and timestamp
            var mutable_entry = self.entries.getPtr(hash).?;
            mutable_entry.access_count += 1;
            mutable_entry.timestamp = std.time.timestamp();

            return cache_path;
        }

        print("❌ Cache miss: {s}\n", .{hash[0..16]});
        return null;
    }

    pub fn storeBuild(self: *BuildCache, hash: []const u8, source_path: []const u8) !void {
        const cache_filename = try std.fmt.allocPrint(self.allocator, "{s}.tar.zst", .{hash});
        defer self.allocator.free(cache_filename);

        const cache_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, cache_filename });
        defer self.allocator.free(cache_path);

        print("==> Storing build in cache: {s}\n", .{cache_filename});

        // Compress and store the build directory
        try self.compressDirectory(source_path, cache_path);

        const file_stat = try std.fs.cwd().statFile(cache_path);

        const entry = CacheEntry{
            .hash = try self.allocator.dupe(u8, hash),
            .path = try self.allocator.dupe(u8, cache_filename),
            .size = file_stat.size,
            .timestamp = std.time.timestamp(),
            .access_count = 1,
        };

        try self.entries.put(try self.allocator.dupe(u8, hash), entry);
        self.current_size += file_stat.size;

        // Clean up old entries if needed
        try self.cleanup();

        try self.saveCacheIndex();
    }

    fn compressDirectory(self: *BuildCache, source_dir: []const u8, dest_file: []const u8) !void {
        // Use tar + zstd for compression
        var child = std.process.Child.init(&[_][]const u8{
            "tar",
            "--use-compress-program=zstd",
            "-cf",
            dest_file,
            "-C",
            source_dir,
            ".",
        }, self.allocator);

        const result = try child.spawnAndWait();
        if (result != .Exited or result.Exited != 0) {
            return error.CompressionFailed;
        }
    }

    pub fn extractBuild(self: *BuildCache, cache_path: []const u8, dest_dir: []const u8) !void {
        print("==> Extracting cached build to: {s}\n", .{dest_dir});

        // Create destination directory
        std.fs.cwd().makeDir(dest_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Extract tar.zst
        var child = std.process.Child.init(&[_][]const u8{
            "tar",
            "--use-compress-program=zstd",
            "-xf",
            cache_path,
            "-C",
            dest_dir,
        }, self.allocator);

        const result = try child.spawnAndWait();
        if (result != .Exited or result.Exited != 0) {
            return error.ExtractionFailed;
        }
    }

    fn cleanup(self: *BuildCache) !void {
        if (self.current_size <= self.max_size) return;

        print("==> Cache size limit exceeded, cleaning up...\n", .{});

        // Create list of entries sorted by LRU (least recently used)
        var entries = ArrayList(struct { hash: []const u8, entry: *CacheEntry }).init(self.allocator);
        defer entries.deinit();

        var iterator = self.entries.iterator();
        while (iterator.next()) |kv| {
            try entries.append(.{ .hash = kv.key_ptr.*, .entry = kv.value_ptr });
        }

        // Sort by timestamp (oldest first)
        std.mem.sort(@TypeOf(entries.items[0]), entries.items, {}, struct {
            fn lessThan(context: void, a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
                _ = context;
                return a.entry.timestamp < b.entry.timestamp;
            }
        }.lessThan);

        // Remove oldest entries until we're under the limit
        for (entries.items) |item| {
            if (self.current_size <= self.max_size * 80 / 100) break; // Keep 20% buffer

            const cache_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, item.entry.path });
            defer self.allocator.free(cache_path);

            std.fs.cwd().deleteFile(cache_path) catch {};

            self.current_size -= item.entry.size;
            print("    Removed cached build: {s}\n", .{item.hash[0..16]});

            // Remove from entries map
            if (self.entries.fetchRemove(item.hash)) |removed| {
                removed.value.deinit(self.allocator);
                self.allocator.free(removed.key);
            }
        }

        print("✅ Cache cleanup completed, size: {d}MB\n", .{self.current_size / 1024 / 1024});
    }

    pub fn getStats(self: *BuildCache) void {
        print("==> Cache Statistics:\n", .{});
        print("    Entries: {d}\n", .{self.entries.count()});
        print("    Size: {d}MB / {d}MB\n", .{ self.current_size / 1024 / 1024, self.max_size / 1024 / 1024 });
        print("    Location: {s}\n", .{self.cache_dir});
    }
};
