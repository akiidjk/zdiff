const std = @import("std");

const Token = struct {
    start: usize,
    len: usize,
    id: usize,
};

pub fn tokenizeBy(allocator: std.mem.Allocator, text: []const u8, separator: u8, internMap: *std.StringHashMap(usize)) ![]Token {
    var index: usize = 0;
    var start: usize = 0;
    var id: usize = 0;

    var tokens: std.ArrayList(Token) = .empty;
    while (index < text.len) : (index += 1) {
        if (text[index] == separator) {
            const key = text[start..index];
            const value = internMap.get(key);
            try tokens.append(allocator, .{
                .id = value orelse id,

                .len = index - start,
                .start = start,
            });

            if (value == null) {
                try internMap.put(key, id);
                id += 1;
            }

            start = index;
        }
    }

    try tokens.append(allocator, .{
        .id = id,
        .len = index - start,
        .start = start,
    });

    return tokens.toOwnedSlice(allocator);
}
