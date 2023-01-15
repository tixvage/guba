const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl2");
const Buffer = @import("buffer.zig");
const Font = @import("font.zig");

pub const Mode = enum {
    file_browser,
    text_editor,
};

pub var mode = Mode.file_browser;
pub var current_buffer: ?*Buffer = null;
pub var font: Font = undefined;
pub var window: *c.SDL_Window = undefined;
pub var renderer: *c.SDL_Renderer = undefined;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;

pub fn changeBuffer(buffer: *Buffer) void {
    if (current_buffer) |old_buffer| {
        old_buffer.deinit();
        allocator.destroy(old_buffer);
    }
    current_buffer = buffer;
}
