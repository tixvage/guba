//TODO: remove function parameters that we can already access via `globals.zig`

const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const freetype = @import("freetype");
const c = @import("sdl2");
const rn = @import("rendering.zig");
const globals = @import("globals.zig");
const Font = @import("font.zig");
const Buffer = @import("buffer.zig");
const Browser = @import("browser.zig");

const allocator = globals.allocator;

const Mode = enum {
    file_browser,
    text_editor,
};

pub fn main() !void {
    defer _ = globals.gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next().?;
    const filename = args.next();

    _ = c.SDL_Init(c.SDL_INIT_EVERYTHING);
    defer _ = c.SDL_Quit();
    globals.window = c.SDL_CreateWindow("guba", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 600, c.SDL_WINDOW_RESIZABLE).?;
    defer _ = c.SDL_DestroyWindow(globals.window);
    globals.renderer = c.SDL_CreateRenderer(globals.window, -1, c.SDL_RENDERER_ACCELERATED).?;
    defer _ = c.SDL_DestroyRenderer(globals.renderer);

    globals.font = try Font.init(allocator, globals.renderer, "SourceCodePro-Medium.ttf", 10);
    defer globals.font.deinit();
    if (filename) |path| {
        var buffer = try allocator.create(Buffer);
        buffer.* = try Buffer.init(allocator, path, globals.window, &globals.font);
        globals.current_buffer = buffer;
        globals.mode = .text_editor;
    }
    defer if (globals.current_buffer) |buffer| {
        buffer.deinit();
        allocator.destroy(buffer);
    };
    var browser = try Browser.init(allocator, ".");
    defer browser.deinit();

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

                        var final_w = @divTrunc(new_x, globals.font.width) * globals.font.width;
                        var final_h = @divTrunc(new_y, globals.font.height) * globals.font.height + @divTrunc(globals.font.height, 4);

                        c.SDL_SetWindowSize(globals.window, final_w, final_h);

                        if (globals.current_buffer) |buffer| {
                            buffer.active_text.y = buffer.active_text.x + @divTrunc(final_h, globals.font.height);
                            buffer.cursor.y = @min(buffer.cursor.y, buffer.active_text.y - buffer.active_text.x - 1);
                            const line = buffer.getCurrentLine();
                            const line_len = @intCast(i32, try std.unicode.utf8CountCodepoints(line));
                            buffer.cursor.x = @min(buffer.cursor.x, line_len);
                        }
                    }
                },
                c.SDL_KEYDOWN => {
                    var sc = event.key.keysym.scancode;
                    if (sc == c.SDL_SCANCODE_F3) {
                        globals.mode = if (globals.mode == .text_editor) .file_browser else .text_editor;
                    }
                    switch (globals.mode) {
                        .text_editor => try globals.current_buffer.?.onKeydown(sc),
                        .file_browser => try browser.onKeydown(sc),
                    }
                },
                c.SDL_TEXTINPUT => {
                    var input = event.text.text;
                    var i: usize = 0;
                    while (input[i] != 0) : (i += 1) {}
                    if (globals.mode == .text_editor) {
                        try globals.current_buffer.?.onTextInput(input[0..i]);
                    }
                },
                else => {},
            }
        }
        _ = c.SDL_SetRenderDrawColor(globals.renderer, 24, 24, 24, 255);
        _ = c.SDL_RenderClear(globals.renderer);
        switch (globals.mode) {
            .text_editor => try globals.current_buffer.?.render(globals.renderer),
            .file_browser => try browser.render(globals.renderer, &globals.font),
        }
        c.SDL_RenderPresent(globals.renderer);
        c.SDL_Delay(1000 / 60);
    }
}
