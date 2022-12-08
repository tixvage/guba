const std = @import("std");
const c = @import("sdl2");

const rn = @import("rendering.zig");
const su = @import("string_utils.zig");
const settings = @import("settings.zig");

const Font = @import("font.zig");

const print = std.debug.print;

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
        const line_number = try std.fmt.allocPrint(self.allocator, "{d}", .{begin + 1});
        defer self.allocator.free(line_number);

        _ = c.SDL_SetRenderDrawColor(renderer, 0x68, 0x68, 0x68, 0xff);
        var line_number_x: i32 = 3;
        for (line_number) |ch| {
            rn.renderCharacter(renderer, self.font, (line_number_x - @intCast(i32, line_number.len)) * self.font.width, (y + 1) * self.font.height, ch);
            line_number_x += 1;
        }

        const line = self.file.items[begin].items;
        const as_unicode = try su.utf8ToUnicode(self.allocator, line);
        defer as_unicode.deinit();

        _ = c.SDL_SetRenderDrawColor(renderer, 0xbc, 0x7c, 0x2c, 0xff);
        for (as_unicode.items) |ch| {
            //TODO: tab support
            rn.renderCharacter(renderer, self.font, (x + 5) * self.font.width, (y + 1) * self.font.height, ch);
            x += 1;
        }
        y += 1;
        x = 0;
    }

    _ = c.SDL_SetRenderDrawColor(renderer, 0xaa, 0xaa, 0xee, 0xff);
    var cursor_rect = c.SDL_Rect{ .x = (self.cursor.x + 5) * self.font.width, .y = (self.cursor.y * self.font.height) + @divTrunc(self.font.height, 4), .w = self.font.width, .h = self.font.height };
    _ = c.SDL_RenderDrawRect(renderer, &cursor_rect);

    _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_SetRenderDrawColor(renderer, 0xaa, 0xaa, 0xaa, 20);
    //TODO: I am too lazy to get window width and calculate proper width of highlighter
    var line_highlighter = c.SDL_Rect{ .x = 5 * self.font.width, .y = (self.cursor.y * self.font.height) + @divTrunc(self.font.height, 4), .w = 1000, .h = self.font.height };
    _ = c.SDL_RenderFillRect(renderer, &line_highlighter);
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

    const keys = c.SDL_GetKeyboardState(null);
    for (settings.keybindings) |keybinding| {
        if (keys[keybinding.mod_key] == 1 and sc == keybinding.main_key) {
            try keybinding.handler(self);
            //TODO: do we really need to return?
            return;
        }
    }

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
            try self.save();
        },
        c.SDL_SCANCODE_DELETE => {
            if (line.items.len == 0) {
                if (self.file.items.len <= 1 or line_number + 1 >= self.file.items.len) return;
                const deleted_line = self.file.orderedRemove(line_number);
                deleted_line.deinit();
            } else if (self.cursor.x == line.items.len) {
                if (line_number + 1 >= self.file.items.len) return;
                var line_next = &self.file.items[line_number + 1];
                try line.appendSlice(line_next.items);
                const deleted_line = self.file.orderedRemove(line_number + 1);
                deleted_line.deinit();
            } else {
                var line_as_unicode = try su.utf8ToUnicode(self.allocator, line.items);
                defer line_as_unicode.deinit();
                _ = line_as_unicode.orderedRemove(@intCast(usize, self.cursor.x));
                try su.updateUtf8(line, line_as_unicode.items);
            }
        },
        else => {},
    }
}

pub fn save(self: *Self) !void {
    const file = try std.fs.cwd().createFile(self.name, .{});
    defer file.close();
    for (self.file.items) |line| {
        try file.writer().print("{s}\n", .{line.items});
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

pub fn saveHorizontal(self: *Self) void {
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
