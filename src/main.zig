const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const freetype = @import("freetype");
const c = @import("sdl2");
const rn = @import("rendering.zig");
const Font = @import("font.zig");
const Buffer = @import("buffer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;
    defer _ = gpa.deinit();

    var args = std.process.args();
    const exec = args.next().?;
    const filename = args.next();
    if (filename == null) {
        print("usage: {s} <filepath>\n", .{exec});
        std.process.exit(1);
    }

    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);
    defer _ = c.SDL_Quit();
    var window = c.SDL_CreateWindow("guba", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 600, 0) orelse @panic("could not init window");
    defer _ = c.SDL_DestroyWindow(window);
    var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse @panic("could not init renderer");
    defer _ = c.SDL_DestroyRenderer(renderer);

    var font = try Font.init(allocator, renderer, "SourceCodePro-Medium.ttf", 10);
    defer font.deinit();
    var buffer = try Buffer.init(allocator, filename.?, window, &font);
    defer buffer.deinit();

    var quit = false;

    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_WINDOWEVENT => {
                    if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED) {
                        var new_x = event.window.data1;
                        var new_y = event.window.data2;

                        var final_w = @divTrunc(new_x, font.width) * font.width;
                        var final_h = @divTrunc(new_y, font.height) * font.height + @divTrunc(font.height, 4);

                        c.SDL_SetWindowSize(window, final_w, final_h);

                        buffer.active_text.y = buffer.active_text.x + @divTrunc(final_h, font.height);
                        buffer.cursor.y = @min(buffer.cursor.y, buffer.active_text.y - buffer.active_text.x - 1);
                        const line = buffer.getCurrentLine();
                        const line_len = @intCast(i32, try std.unicode.utf8CountCodepoints(line));
                        buffer.cursor.x = @min(buffer.cursor.x, line_len);
                    }
                },
                c.SDL_KEYDOWN => {
                    var sc = event.key.keysym.scancode;
                    try buffer.onKeydown(sc);
                },
                c.SDL_TEXTINPUT => {
                    var input = event.text.text;
                    var i: usize = 0;
                    while (input[i] != 0) : (i += 1) {}
                    try buffer.onTextinput(input[0..i]);
                },
                else => {},
            }
        }
        _ = c.SDL_SetRenderDrawColor(renderer, 24, 24, 24, 255);
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_SetRenderDrawColor(renderer, 0xcc, 0x8c, 0x3c, 255);
        try buffer.render(renderer);
        c.SDL_RenderPresent(renderer);
        c.SDL_Delay(1000 / 60);
    }
}
