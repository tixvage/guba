const std = @import("std");
const c = @import("sdl2");
const Buffer = @import("buffer.zig");

const Handler = *const fn (*Buffer) anyerror!void;

const Self = @This();

mod_key: ?c.SDL_Scancode = c.SDL_SCANCODE_LCTRL,
main_key: c.SDL_Scancode,
handler: Handler,
