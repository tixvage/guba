const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const freetype = @import("freetype");
const c = @import("sdl2");
const rn = @import("rendering.zig");
const Font = @import("font.zig");
const Buffer = @import("buffer.zig");
const Browser = @import("browser.zig");

const Mode = enum {
    file_browser,
    text_editor,
};

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
    var window = c.SDL_CreateWindow("guba", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 600, c.SDL_WINDOW_RESIZABLE).?;
    defer _ = c.SDL_DestroyWindow(window);
    var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED).?;
    defer _ = c.SDL_DestroyRenderer(renderer);

    var font = try Font.init(allocator, renderer, "SourceCodePro-Medium.ttf", 10);
    defer font.deinit();
    var buffer = try Buffer.init(allocator, filename.?, window, &font);
    defer buffer.deinit();
    var browser = try Browser.init(allocator, ".");
    defer browser.deinit();

    var quit = false;
    var mode = Mode.text_editor;

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
                    if (sc == c.SDL_SCANCODE_F3) {
                        mode = if (mode == .text_editor) .file_browser else .text_editor;
                    }
                    switch (mode) {
                        .text_editor => try buffer.onKeydown(sc),
                        .file_browser => {},
                    }
                },
                c.SDL_TEXTINPUT => {
                    var input = event.text.text;
                    var i: usize = 0;
                    while (input[i] != 0) : (i += 1) {}
                    if (mode == .text_editor) {
                        try buffer.onTextInput(input[0..i]);
                    }
                },
                else => {},
            }
        }
        _ = c.SDL_SetRenderDrawColor(renderer, 24, 24, 24, 255);
        _ = c.SDL_RenderClear(renderer);
        switch (mode) {
            .text_editor => try buffer.render(renderer),
            .file_browser => {
                //var y: i32 = 0;
                //for (entries.items) |entry| {
                //    var x: i32 = 0;
                //    for (entry.name) |ch| {
                //        _ = c.SDL_SetRenderDrawColor(renderer, 255, 24, 24, 255);
                //        rn.renderCharacter(renderer, &font, 50 + (x * font.width), (y + 1) * font.height, ch);
                //        x += 1;
                //    }
                //    y += 1;
                //}
            },
        }
        c.SDL_RenderPresent(renderer);
        c.SDL_Delay(1000 / 60);
    }
}
