const std = @import("std");
const c = @import("sdl2");
const su = @import("string_utils.zig");

const Buffer = @import("buffer.zig");
const Keybinding = @import("keybinding.zig");

pub const keybindings = [_]Keybinding{
    .{ .main_key = c.SDL_SCANCODE_A, .handler = goBol },
    .{ .main_key = c.SDL_SCANCODE_E, .handler = goEol },
    .{ .main_key = c.SDL_SCANCODE_S, .handler = Buffer.save },
    .{ .mod_key = null, .main_key = c.SDL_SCANCODE_F11, .handler = toggleFullscreen },
    .{ .mod_key = c.SDL_SCANCODE_LSHIFT, .main_key = c.SDL_SCANCODE_DELETE, .handler = deleteCurrentLine },
    .{ .mod_key = c.SDL_SCANCODE_LCTRL, .main_key = c.SDL_SCANCODE_RIGHT, .handler = goNextWord },
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
    try buffer.tryRecoverHorizontal();
}

fn goNextWord(buffer: *Buffer) !void {
    const line = buffer.getCurrentLine();
    const line_as_unicode = try su.utf8ToUnicode(buffer.allocator, line);
    const line_len = line_as_unicode.items.len;
    defer line_as_unicode.deinit();

    const current_pos = buffer.cursor.x;
    var it = std.mem.split(u32, line_as_unicode.items[@intCast(usize, current_pos)..], &.{' '});
    if (it.next()) |_| {
        if (it.index) |index| {
            buffer.cursor.x = @intCast(i32, index) + current_pos;
        } else {
            if (buffer.cursor.x != @intCast(i32, line_len)) {
                buffer.cursor.x = @intCast(i32, line_len);
            } else {
                //next line request
                std.debug.print("triggered", .{});
            }
        }
    }
    buffer.saveHorizontal();
}
