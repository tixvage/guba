const c = @import("sdl2");
const Font = @import("font.zig");

pub fn renderCharacter(renderer: *c.SDL_Renderer, font: *Font, x: i32, y: i32, ch: u32) void {
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    _ = c.SDL_GetRenderDrawColor(renderer, &r, &g, &b, &a);
    _ = c.SDL_SetTextureColorMod(font.atlas, r, g, b);
    _ = c.SDL_SetTextureAlphaMod(font.atlas, a);
    var ch_info = font.info[ch];
    var w = @intCast(c_int, ch_info.x1 - ch_info.x0);
    var h = @intCast(c_int, ch_info.y1 - ch_info.y0);
    var src: c.SDL_Rect = .{ .x = @intCast(c_int, ch_info.x0), .y = @intCast(c_int, ch_info.y0), .w = w, .h = h };
    var dest: c.SDL_Rect = .{ .x = @intCast(c_int, x + ch_info.x_off), .y = @intCast(c_int, y - ch_info.y_off), .w = w, .h = h };
    _ = c.SDL_RenderCopy(renderer, font.atlas, &src, &dest);
}
