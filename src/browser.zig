const std = @import("std");
const c = @import("sdl2");
const rn = @import("rendering.zig");
const FsEntry = std.fs.IterableDir.Entry;
const Font = @import("font.zig");

const Entry = struct {
    name: []u8,
    kind: enum { folder, file },
};

const Self = @This();

current_abspath: std.ArrayList(u8),
entries: std.ArrayList(Entry),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, initial_path: []const u8) !Self {
    var self = Self{
        .current_abspath = std.ArrayList(u8).init(allocator),
        .entries = std.ArrayList(Entry).init(allocator),
        .allocator = allocator,
    };
    try self.updateEntries(initial_path);

    return self;
}

pub fn updateEntries(self: *Self, parent_path: []const u8) !void {
    self.clearEntries();

    const cwd = std.fs.cwd();

    const new_dir = try cwd.openDir(parent_path, .{});
    try new_dir.setAsCwd();
    try self.current_abspath.appendSlice(parent_path);
    try self.current_abspath.append('/');

    const iterable_dir = try new_dir.openIterableDir(".", .{});
    var dir_iterator = iterable_dir.iterate();
    while (try dir_iterator.next()) |a| {
        var name = try self.allocator.alloc(u8, a.name.len);
        std.mem.copy(u8, name, a.name);
        const entry = Entry{
            .name = name,
            .kind = if (a.kind == .Directory) .folder else .file,
        };
        if (entry.kind == .folder) try self.entries.insert(0, entry) else try self.entries.append(entry);
    }
}

pub fn render(self: *Self, renderer: *c.SDL_Renderer, font: *Font) !void {
    _ = c.SDL_SetRenderDrawColor(renderer, 255, 24, 24, 255);
    for (self.entries.items) |entry, y| {
        for (entry.name) |ch, x| {
            rn.renderCharacter(renderer, font, 50 + (@intCast(i32, x) * font.width), @intCast(i32, y + 1) * font.height, ch);
        }
    }
}

fn clearEntries(self: *Self) void {
    for (self.entries.items) |entry| {
        self.allocator.free(entry.name);
    }
    self.entries.clearAndFree();
}

pub fn deinit(self: *Self) void {
    self.clearEntries();
    self.current_abspath.deinit();
    self.entries.deinit();
}
