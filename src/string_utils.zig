const std = @import("std");

pub const Utf8Line = std.ArrayList(u8);
pub const UnicodeLine = std.ArrayList(u32);

pub fn utf8ToUnicode(allocator: std.mem.Allocator, utf8: []const u8) !UnicodeLine {
    var unicode = UnicodeLine.init(allocator);

    const view = try std.unicode.Utf8View.init(utf8);
    var iterator = view.iterator();
    while (iterator.nextCodepointSlice()) |codepoint| {
        var ch = try std.unicode.utf8Decode(codepoint);
        try unicode.append(ch);
    }

    return unicode;
}

pub fn unicodeToUtf8(allocator: std.mem.Allocator, unicode: []const u32) !Utf8Line {
    var utf8 = Utf8Line.init(allocator);
    try updateUtf8(&utf8, unicode);
    return utf8;
}

pub fn updateUtf8(utf8: *Utf8Line, unicode: []const u32) !void {
    if (utf8.items.len != 0) utf8.clearAndFree();
    for (unicode) |ch| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(@intCast(u21, ch), &buf);
        try utf8.appendSlice(buf[0..len]);
    }
}
