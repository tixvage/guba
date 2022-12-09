const std = @import("std");
const c = @import("sdl2");
const Buffer = @import("buffer.zig");
const Keybinding = @import("keybinding.zig");

pub const keybindings = [_]Keybinding{
    .{ .main_key = c.SDL_SCANCODE_A, .handler = goBol },
    .{ .main_key = c.SDL_SCANCODE_E, .handler = goEol },
    .{ .main_key = c.SDL_SCANCODE_S, .handler = Buffer.save },
    .{ .mod_key = null, .main_key = c.SDL_SCANCODE_F11, .handler = toggleFullscreen },
    .{ .mod_key = c.SDL_SCANCODE_LSHIFT, .main_key = c.SDL_SCANCODE_DELETE, .handler = deleteCurrentLine },
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

var fullscreen = false;
fn toggleFullscreen(buffer: *Buffer) !void {
    fullscreen = !fullscreen;
    _ = c.SDL_SetWindowFullscreen(buffer.window, if (fullscreen) c.SDL_WINDOW_FULLSCREEN_DESKTOP else 0);
}

fn deleteCurrentLine(buffer: *Buffer) !void {
    const line_number = buffer.getLineNumber();
    const deleted_line = buffer.file.orderedRemove(line_number);
    deleted_line.deinit();
}
