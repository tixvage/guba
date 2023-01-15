const std = @import("std");
const c = @import("sdl2");
const rn = @import("rendering.zig");
const globals = @import("globals.zig");
const Font = @import("font.zig");
const Buffer = @import("buffer.zig");

const Entry = struct {
    name: []u8,
    kind: enum { folder, file },
};

const Self = @This();

current_abspath: std.ArrayList(u8),
entries: std.ArrayList(Entry),
allocator: std.mem.Allocator,
index: usize,

pub fn init(allocator: std.mem.Allocator, initial_path: []const u8) !Self {
    var self = Self{
        .current_abspath = std.ArrayList(u8).init(allocator),
        .entries = std.ArrayList(Entry).init(allocator),
        .allocator = allocator,
        .index = 0,
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
    _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_SetRenderDrawColor(renderer, 0xaa, 0xaa, 0xaa, 0x77);
    var line_rect = c.SDL_Rect{ .x = 50, .y = (@intCast(i32, self.index) * font.height) + @divTrunc(font.height, 4), .w = font.width * @intCast(i32, self.entries.items[self.index].name.len), .h = font.height };
    _ = c.SDL_RenderFillRect(renderer, &line_rect);
}

pub fn onKeydown(self: *Self, sc: c.SDL_Scancode) !void {
    switch (sc) {
        c.SDL_SCANCODE_UP => {
            self.index = @intCast(usize, @max(0, @intCast(i32, self.index) - 1));
        },
        c.SDL_SCANCODE_DOWN => {
            self.index = @min(self.entries.items.len - 1, self.index + 1);
        },
        c.SDL_SCANCODE_RETURN => {
            const entry = self.entries.items[self.index];
            const old_name = entry.name;
            var name = try self.allocator.alloc(u8, old_name.len);
            defer self.allocator.free(name);
            std.mem.copy(u8, name, old_name);
            switch (entry.kind) {
                .folder => try self.updateEntries(name),
                .file => {
                    var buffer = try globals.allocator.create(Buffer);
                    buffer.* = try Buffer.init(globals.allocator, name, globals.window, &globals.font);
                    globals.changeBuffer(buffer);
                    globals.mode = .text_editor;
                },
            }
            self.index = 0;
        },
        else => {},
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
