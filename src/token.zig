const std = @import("std");

const Token = struct {
    start: usize,
    len: usize,
    id: usize,
};

pub fn tokenizeBy(allocator: std.mem.Allocator, text: []const u8, separator: u8, internMap: *std.array_hash_map.String(usize)) ![]Token {
    var index: usize = 0;
    var start: usize = 0;
    var id: usize = if (internMap.count() > 0) internMap.values()[internMap.count() - 1] + 1 else 0;
    std.debug.print("{d} {any} {d}\n", .{ internMap.count(), internMap.values(), id });

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
                try internMap.put(allocator, key, id);
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
