const std = @import("std");
const c = @import("sdl2");
const Buffer = @import("buffer.zig");
const Keybinding = @import("keybinding.zig");

pub const keybindings = [_]Keybinding{
    .{ .main_key = c.SDL_SCANCODE_A, .handler = goBol },
    .{ .main_key = c.SDL_SCANCODE_E, .handler = goEol },
    .{ .main_key = c.SDL_SCANCODE_S, .handler = Buffer.save },
};

fn goBol(buffer: *Buffer) !void {
    buffer.cursor.x = 0;
    buffer.saveHorizontal();
}

fn goEol(buffer: *Buffer) !void {
    const line_number = buffer.getLineNumber();
    var line = &buffer.file.items[line_number];
    buffer.cursor.x = @intCast(i32, try std.unicode.utf8CountCodepoints(line.items));
    buffer.saveHorizontal();
}
