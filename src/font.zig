const std = @import("std");
const freetype = @import("freetype");
const c = @import("sdl2");

pub const GlyphInfo = struct { x0: u32, y0: u32, x1: u32, y1: u32, x_off: i32, y_off: i32, advance: u32 };

const Self = @This();

atlas: *c.SDL_Texture,
info: []GlyphInfo,
height: i32,
width: i32,
size: i32,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, path: []const u8, size: i32) !Self {
    const lib = try freetype.Library.init();
    defer lib.deinit();

    const face = try lib.createFace(path, 0);
    try face.setCharSize(0, size << 6, 96, 96);
    var height = calculateHeight(face);
    var width: i32 = 0;
    var num_glyphs = @intCast(usize, face.numGlyphs());
    var info = try allocator.alloc(GlyphInfo, num_glyphs);
    const metrics = face.size().metrics();
    var max_dim = @intCast(u32, (1 + (metrics.height >> 6)) * @floatToInt(i32, std.math.ceil(std.math.sqrt(@intToFloat(f32, num_glyphs)))));
    var tex_width: u32 = 1;
    while (tex_width < max_dim) tex_width <<= 1;
    var tex_height: u32 = tex_width;

    var pen_x: u32 = 0;
    var pen_y: u32 = 0;
    var pixels = try allocator.alloc(u8, @intCast(usize, tex_width * tex_height));
    defer allocator.free(pixels);

    var i: usize = 0;
    while (i < num_glyphs) : (i += 1) {
        try face.loadChar(@intCast(u32, i), .{ .force_autohint = true, .render = true });
        const glyph = face.glyph();
        const bmp = glyph.bitmap();

        if (pen_x + bmp.width() >= tex_height) {
            pen_x = 0;
            pen_y += @intCast(u32, (metrics.height >> 6) + 1);
        }

        var row: usize = 0;
        while (row < bmp.rows()) : (row += 1) {
            var col: usize = 0;
            while (col < bmp.width()) : (col += 1) {
                var x = pen_x + @intCast(u32, col);
                var y = pen_y + @intCast(u32, row);
                const offset = @intCast(usize, y * tex_width + x);
                pixels[offset] = bmp.buffer().?[row * @intCast(usize, bmp.pitch()) + col];
            }
        }

        info[i].x0 = pen_x;
        info[i].y0 = pen_y;
        info[i].x1 = pen_x + bmp.width();
        info[i].y1 = pen_y + bmp.rows();

        info[i].x_off = face.glyph().bitmapLeft();
        info[i].y_off = face.glyph().bitmapTop();
        info[i].advance = @intCast(u32, face.glyph().advance().x >> 6);

        pen_x += bmp.width();
        width = @max(width, @intCast(i32, face.glyph().advance().x) >> 6);
    }

    return .{
        .atlas = try createTexture(allocator, renderer, pixels, @intCast(c_int, tex_width), @intCast(c_int, tex_height)),
        .info = info,
        .height = height,
        .width = width,
        .size = size,
        .allocator = allocator,
    };
}

fn calculateHeight(face: freetype.Face) i32 {
    var y_scale = @intCast(i32, face.size().metrics().y_scale);
    return @divExact((freetype.mulFix(face.height(), y_scale) + 63) & -64, 64);
}

fn createTexture(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, pixels: []u8, tex_width: c_int, tex_height: c_int) !*c.SDL_Texture {
    var atlas = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, tex_width, tex_height).?;
    _ = c.SDL_SetTextureBlendMode(atlas, c.SDL_BLENDMODE_BLEND);
    var size = @intCast(usize, tex_height * tex_width);
    var sdl_pixels = try allocator.alloc(u32, size);
    defer allocator.free(sdl_pixels);
    var format = c.SDL_AllocFormat(c.SDL_PIXELFORMAT_RGBA32);
    var i: usize = 0;
    while (i < size) : (i += 1) {
        sdl_pixels[i] = c.SDL_MapRGBA(format, pixels[i], pixels[i], pixels[i], pixels[i]);
    }
    _ = c.SDL_UpdateTexture(atlas, null, @ptrCast(*const anyopaque, sdl_pixels), tex_width * @sizeOf(u32));

    return atlas;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.info);
}
