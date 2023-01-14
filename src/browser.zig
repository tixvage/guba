const std = @import("std");
const Entry = std.fs.IterableDir.Entry;

const Self = @This();

current_abspath: std.ArrayList(u8),
entries: std.ArrayList(Entry),

pub fn init(allocator: std.mem.Allocator, initial_path: []const u8) !Self {
    var self = Self{
        .current_abspath = std.ArrayList(u8).init(allocator),
        .entries = std.ArrayList(Entry).init(allocator),
    };
    try self.updateEntries(".");
    _ = initial_path;

    return self;
}

pub fn updateEntries(self: *Self, parent_path: []const u8) !void {
    self.entries.clearAndFree();
    const cwd = std.fs.cwd();

    const new_dir = try cwd.openDir(parent_path, .{});
    try new_dir.setAsCwd();
    try self.current_abspath.appendSlice(parent_path);
    try self.current_abspath.append('/');

    const iterable_dir = try new_dir.openIterableDir(".", .{});
    var dir_iterator = iterable_dir.iterate();
    while (try dir_iterator.next()) |a| {
        try self.entries.append(a);
    }
}

pub fn deinit(self: *Self) void {
    self.current_abspath.deinit();
    self.entries.deinit();
}
