const std = @import("std");

pub const Token = struct {
    start: usize,
    len: usize,
};

pub const Tokenized = struct {
    tokens: []Token,
    ids: []usize,
};

pub fn tokenizeBy(allocator: std.mem.Allocator, text: []const u8, separator: u8, internMap: *std.array_hash_map.String(usize)) !Tokenized {
    var index: usize = 0;
    var start: usize = 0;
    var id: usize = if (internMap.count() > 0) internMap.values()[internMap.count() - 1] + 1 else 0;
    std.debug.print("{d} {any} {d}\n", .{ internMap.count(), internMap.values(), id });

    var tokens: std.ArrayList(Token) = .empty;
    var ids: std.ArrayList(usize) = .empty;

    while (index < text.len) : (index += 1) {
        if (text[index] == separator) {
            const key = text[start..index];
            const value = internMap.get(key);

            if (value == null) {
                try internMap.put(allocator, key, id);

                try tokens.append(allocator, .{
                    .len = index - start,
                    .start = start,
                });

                try ids.append(allocator, id);

                id += 1;
            } else {
                try tokens.append(allocator, .{
                    .len = index - start,
                    .start = start,
                });
                try ids.append(allocator, value orelse id);
            }

            start = index;
        }
    }

    const key = text[start..index];
    const value = internMap.get(key);

    if (value == null) {
        try internMap.put(allocator, key, id);

        try tokens.append(allocator, .{
            .len = index - start,
            .start = start,
        });
        try ids.append(allocator, id);

        id += 1;
    } else {
        try tokens.append(allocator, .{
            .len = index - start,
            .start = start,
        });
        try ids.append(allocator, value orelse id);
    }

    return .{
        .ids = try ids.toOwnedSlice(allocator),
        .tokens = try tokens.toOwnedSlice(allocator),
    };
}
