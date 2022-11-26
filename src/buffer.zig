const std = @import("std");
const c = @import("sdl2");
const Font = @import("font.zig");
const rn = @import("rendering.zig");
const su = @import("string_utils.zig");
const print = std.debug.print;
const stdio = @cImport(@cInclude("stdio.h"));

pub const Utf8Line = su.Utf8Line;
pub const UnicodeLine = su.UnicodeLine;
pub const File = std.ArrayList(Utf8Line);
pub const Vec2 = struct { x: i32 = 0, y: i32 = 0 };
pub const Range = Vec2;

pub const Cursor = struct {
    x: i32 = 0,
    y: i32 = 0,
    last_horizontal_position: i32 = -1,
};

fn fileFromText(allocator: std.mem.Allocator, text: []const u8) !File {
    var file = File.init(allocator);

    var start: usize = 0;
    var end: usize = 0;

    for (text) |ch, i| {
        if (ch == '\n') {
            end = i;
            var line = Utf8Line.init(allocator);
            try line.appendSlice(text[start..end]);
            try file.append(line);
            start = i + 1;
        }
    }

    //probably a new file
    if (file.items.len == 0) {
        var line = Utf8Line.init(allocator);
        try file.append(line);
    }

    return file;
}

const Self = @This();

file: File,
cursor: Cursor = .{},
active_text: Range,
name: []const u8,
font: *Font,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, path: []const u8, window: *c.SDL_Window, font: *Font) !Self {
    var text: []u8 = undefined;
    //85MB limit
    const try_reading = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 85);
    if (try_reading) |success| {
        text = success;
    } else |err| switch (err) {
        error.FileNotFound => {
            const file = try std.fs.cwd().createFile(path, .{});
            file.close();
            return init(allocator, path, window, font);
        },
        else => {},
    }
    defer allocator.free(text);
    var file = try fileFromText(allocator, text);

    var w_w: i32 = 0;
    var w_h: i32 = 0;
    c.SDL_GetWindowSize(window, &w_w, &w_h);
    return .{
        .file = file,
        .name = path,
        .allocator = allocator,
        .active_text = .{ .y = @divTrunc(w_h, font.height) },
        .font = font,
    };
}

pub fn render(self: *Self, renderer: *c.SDL_Renderer) !void {
    var begin = @max(@intCast(usize, self.active_text.x), 0);
    var end = @min(@intCast(usize, self.active_text.y), self.file.items.len);
    var y: i32 = 0;
    var x: i32 = 0;
    while (begin < end) : (begin += 1) {
        const view = try std.unicode.Utf8View.init(self.file.items[begin].items);
        var iterator = view.iterator();
        while (iterator.nextCodepointSlice()) |codepoint| {
            var ch = try std.unicode.utf8Decode(codepoint);
            rn.renderCharacter(renderer, self.font, x * self.font.width, (y + 1) * self.font.height, ch);
            x += 1;
        }
        y += 1;
        x = 0;
    }

    _ = c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0x00, 0xff);

    var cursor_rect = c.SDL_Rect{ .x = self.cursor.x * self.font.width, .y = (self.cursor.y * self.font.height) + @divTrunc(self.font.height, 4), .w = self.font.width, .h = self.font.height };
    _ = c.SDL_RenderDrawRect(renderer, &cursor_rect);
}

pub fn onTextinput(self: *Self, input: []const u8) !void {
    var line = &self.file.items[self.getLineNumber()];
    var line_as_unicode = try su.utf8ToUnicode(self.allocator, line.items);
    defer line_as_unicode.deinit();

    const input_as_unicode = @intCast(u32, try std.unicode.utf8Decode(input));
    try line_as_unicode.insert(@intCast(usize, self.cursor.x), input_as_unicode);
    try su.updateUtf8(line, line_as_unicode.items);

    try self.cursorRight();
}

pub fn onKeydown(self: *Self, sc: c.SDL_Scancode) !void {
    const line_number = self.getLineNumber();
    var line = &self.file.items[line_number];

    switch (sc) {
        c.SDL_SCANCODE_LEFT => {
            try self.cursorLeft();
        },
        c.SDL_SCANCODE_RIGHT => {
            try self.cursorRight();
        },
        c.SDL_SCANCODE_UP => {
            try self.cursorUp();
        },
        c.SDL_SCANCODE_DOWN => {
            try self.cursorDown();
        },
        c.SDL_SCANCODE_BACKSPACE => {
            if (self.cursor.x == 0) {
                if (line_number == 0) return;
                var line_before = &self.file.items[line_number - 1];
                const line_len = try std.unicode.utf8CountCodepoints(line_before.items);
                try line_before.appendSlice(line.items);
                const deleted_line = self.file.orderedRemove(line_number);
                deleted_line.deinit();
                try self.cursorUp();
                self.cursor.x = @intCast(i32, line_len);
                self.saveHorizontal();
            } else {
                var line_as_unicode = try su.utf8ToUnicode(self.allocator, line.items);
                defer line_as_unicode.deinit();
                _ = line_as_unicode.orderedRemove(@intCast(usize, self.cursor.x - 1));

                try su.updateUtf8(line, line_as_unicode.items);
                try self.cursorLeft();
            }
        },
        c.SDL_SCANCODE_RETURN => {
            var line_as_unicode = try su.utf8ToUnicode(self.allocator, line.items);
            defer line_as_unicode.deinit();

            const from = @intCast(usize, self.cursor.x);
            const new_str = line_as_unicode.items[from..];
            const old_str = line_as_unicode.items[0..from];

            try su.updateUtf8(line, old_str);
            try self.file.insert(line_number + 1, try su.unicodeToUtf8(self.allocator, new_str));
            try self.cursorDown();
            self.cursor.x = 0;
            self.saveHorizontal();
        },
        c.SDL_SCANCODE_PAGEUP => {
            const range = self.active_text.y - self.active_text.x;
            const amount = range - self.cursor.y - 1;
            self.scroll(-amount);
            self.cursor.y = 0;
            try self.tryRecoverHorizontal();
        },
        c.SDL_SCANCODE_PAGEDOWN => {
            const range = self.active_text.y - self.active_text.x;
            const amount = self.cursor.y;
            self.scroll(amount);
            self.cursor.y = @min(@intCast(i32, self.file.items.len - 1), range - 1);
            try self.tryRecoverHorizontal();
        },
        c.SDL_SCANCODE_F1 => {
            try self.save2();
        },
        c.SDL_SCANCODE_HOME => {
            self.cursor.x = 0;
            self.saveHorizontal();
        },
        c.SDL_SCANCODE_END => {
            self.cursor.x = @intCast(i32, try std.unicode.utf8CountCodepoints(line.items));
            self.saveHorizontal();
        },
        else => {},
    }
}

//TODO: ask that in discord server
fn save(self: *Self) !void {
    const file = try std.fs.cwd().openFile(self.name, .{ .mode = .write_only });
    defer file.close();
    print("line = {d}\n", .{self.file.items.len});
    for (self.file.items) |line| {
        _ = try file.write(line.items);
        _ = try file.write("\n");
    }
}

fn save2(self: *Self) !void {
    var name_cstr = try std.cstr.addNullByte(self.allocator, self.name);
    defer self.allocator.free(name_cstr);
    var file = stdio.fopen(@ptrCast([*c]const u8, name_cstr), "w").?;
    defer _ = stdio.fclose(file);

    for (self.file.items) |line| {
        var line_cstr = try std.cstr.addNullByte(self.allocator, line.items);
        defer self.allocator.free(line_cstr);
        _ = stdio.fprintf(file, "%s\n", @ptrCast([*c]const u8, line_cstr));
    }
}

pub fn cursorRight(self: *Self) !void {
    const line = self.getCurrentLine();
    const line_len = @intCast(i32, try std.unicode.utf8CountCodepoints(line));

    if (self.cursor.x == line_len) {
        if (self.getLineNumber() + 1 == self.file.items.len) return;
        try self.cursorDown();
        self.cursor.x = 0;
    } else self.cursor.x = @min(line_len, self.cursor.x + 1);
    self.saveHorizontal();
}

pub fn cursorLeft(self: *Self) !void {
    if (self.cursor.x == 0) {
        if (self.getLineNumber() == 0) return;
        try self.cursorUp();
        const line = self.getCurrentLine();
        const line_len = @intCast(i32, try std.unicode.utf8CountCodepoints(line));
        self.cursor.x = @intCast(i32, line_len);
    } else self.cursor.x = @max(self.cursor.x - 1, 0);
    self.saveHorizontal();
}

pub fn cursorDown(self: *Self) !void {
    const total_lines = @intCast(i32, self.file.items.len);
    self.cursor.y += 1;
    if (self.cursor.y >= @min(self.active_text.y - self.active_text.x, total_lines - self.active_text.x)) {
        self.cursor.y -= 1;
        self.scroll(1);
    }
    try self.tryRecoverHorizontal();
}

pub fn cursorUp(self: *Self) !void {
    self.cursor.y -= 1;
    if (self.cursor.y < 0) {
        self.cursor.y = 0;
        self.scroll(-1);
    }
    try self.tryRecoverHorizontal();
}

fn tryRecoverHorizontal(self: *Self) !void {
    const line = self.getCurrentLine();
    const line_len = @intCast(i32, try std.unicode.utf8CountCodepoints(line));

    if (self.cursor.last_horizontal_position != -1) self.cursor.x = self.cursor.last_horizontal_position;
    self.cursor.x = @min(@intCast(i32, line_len), self.cursor.x);
}

fn saveHorizontal(self: *Self) void {
    self.cursor.last_horizontal_position = self.cursor.x;
}

fn scroll(self: *Self, amount: i32) void {
    const total_lines = @intCast(i32, self.file.items.len);
    const range = self.active_text.y - self.active_text.x;
    if (self.active_text.x + amount < 0) {
        self.active_text.x = 0;
        self.active_text.y = range;
    } else if (range > total_lines) {
        self.active_text.x = 0;
        self.active_text.y = range;
    } else if (self.active_text.y + amount >= total_lines) {
        self.active_text.y = total_lines;
        self.active_text.x = self.active_text.y - range;
    } else {
        self.active_text.y += amount;
        self.active_text.x += amount;
    }
}

pub fn getCurrentLine(self: *Self) []const u8 {
    const line_number = self.getLineNumber();
    return self.file.items[line_number].items;
}

pub fn getLineNumber(self: *Self) usize {
    var line_number = @intCast(usize, self.active_text.x + self.cursor.y);
    return @min(line_number, self.file.items.len - 1);
}

pub fn deinit(self: *Self) void {
    for (self.file.items) |line| {
        line.deinit();
    }
    self.file.deinit();
}
