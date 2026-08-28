const std = @import("std");

pub const Token = struct {
    start: usize,
    len: usize,
};

pub const Tokenized = struct {
    tokens: []Token,
    ids: []usize,
};

pub const CommonTrim = struct {
    old: []const u8,
    new: []const u8,
    line_offset: usize,
};

fn commonPrefix(old: []const u8, new: []const u8) usize {
    const len = @min(old.len, new.len);
    var i: usize = 0;
    while (i < len and old[i] == new[i]) i += 1;
    return i;
}

fn commonSuffix(old: []const u8, new: []const u8, prefix: usize) usize {
    const len = @min(old.len, new.len) - prefix;
    var i: usize = 0;
    while (i < len and old[old.len - 1 - i] == new[new.len - 1 - i]) i += 1;
    return i;
}

fn prefixStart(text: []const u8, prefix: usize, separator: u8, context: usize) usize {
    var start = if (std.mem.lastIndexOfScalar(u8, text[0..prefix], separator)) |i| i + 1 else 0;
    for (0..context) |_| {
        if (start == 0) break;
        start = if (std.mem.lastIndexOfScalar(u8, text[0 .. start - 1], separator)) |i| i + 1 else 0;
    }
    return start;
}

fn suffixEnd(text: []const u8, suffix: usize, separator: u8, context: usize) usize {
    if (suffix == 0) return text.len;
    const suffix_start = text.len - suffix;
    var end = std.mem.indexOfScalarPos(u8, text, suffix_start, separator) orelse return text.len;
    const included_common_line = suffix_start == 0 or text[suffix_start - 1] == separator;
    const remaining = context -| @intFromBool(included_common_line);
    for (0..remaining) |_| {
        end = std.mem.indexOfScalarPos(u8, text, end + 1, separator) orelse return text.len;
    }
    return end;
}

fn trimCommonImpl(comptime debug: bool, io: if (debug) std.Io else void, old: []const u8, new: []const u8, separator: u8, context: usize) CommonTrim {
    const prefix = blk: {
        if (debug) {
            const start = std.Io.Clock.now(.awake, io);
            const value = commonPrefix(old, new);
            const end = std.Io.Clock.now(.awake, io);
            std.debug.print("[timing] prefix={d} ns\n", .{start.durationTo(end).toNanoseconds()});
            break :blk value;
        }
        break :blk commonPrefix(old, new);
    };
    const suffix = blk: {
        if (debug) {
            const start = std.Io.Clock.now(.awake, io);
            const value = commonSuffix(old, new, prefix);
            const end = std.Io.Clock.now(.awake, io);
            std.debug.print("[timing] suffix={d} ns\n", .{start.durationTo(end).toNanoseconds()});
            break :blk value;
        }
        break :blk commonSuffix(old, new, prefix);
    };

    const start = prefixStart(old, prefix, separator, context);
    var line_offset: usize = 0;
    for (old[0..start]) |byte| if (byte == separator) {
        line_offset += 1;
    };
    return .{
        .old = old[start..@max(start, suffixEnd(old, suffix, separator, context))],
        .new = new[start..@max(start, suffixEnd(new, suffix, separator, context))],
        .line_offset = line_offset,
    };
}

pub fn trimCommon(old: []const u8, new: []const u8, separator: u8, context: usize) CommonTrim {
    return trimCommonImpl(false, {}, old, new, separator, context);
}

pub fn trimCommonDebug(io: std.Io, old: []const u8, new: []const u8, separator: u8, context: usize) CommonTrim {
    return trimCommonImpl(true, io, old, new, separator, context);
}

test "trim common complete lines and retain context" {
    const trimmed = trimCommon("a\nb\nold\nc\nd\n", "a\nb\nnew\nc\nd\n", '\n', 1);
    try std.testing.expectEqualStrings("b\nold\nc", trimmed.old);
    try std.testing.expectEqualStrings("b\nnew\nc", trimmed.new);
    try std.testing.expectEqual(1, trimmed.line_offset);
}

test "trim common keeps exactly one suffix context line" {
    const trimmed = trimCommon("head\nbefore\nremove\nafter\ntail\n", "head\nbefore\nafter\ntail\n", '\n', 1);
    try std.testing.expectEqualStrings("before\nremove\nafter", trimmed.old);
    try std.testing.expectEqualStrings("before\nafter", trimmed.new);
}

pub fn tokenizeBy(allocator: std.mem.Allocator, text: []const u8, separator: u8, internMap: *std.array_hash_map.String(usize)) !Tokenized {
    var index: usize = 0;
    var start: usize = 0;
    var id: usize = if (internMap.count() > 0) internMap.values()[internMap.count() - 1] + 1 else 0;

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

            start = index + 1;
        }
    }

    if (start < index) {
        const key = text[start..index];
        const value = internMap.get(key);
        if (value) |existing| {
            try tokens.append(allocator, .{ .len = index - start, .start = start });
            try ids.append(allocator, existing);
        } else {
            try internMap.put(allocator, key, id);
            try tokens.append(allocator, .{ .len = index - start, .start = start });
            try ids.append(allocator, id);
        }
    }

    return .{
        .ids = try ids.toOwnedSlice(allocator),
        .tokens = try tokens.toOwnedSlice(allocator),
    };
}

test "tokenizeBy does not invent a line after trailing separator" {
    var intern: std.array_hash_map.String(usize) = .empty;
    defer intern.deinit(std.testing.allocator);
    const result = try tokenizeBy(std.testing.allocator, "one\ntwo\n", '\n', &intern);
    defer std.testing.allocator.free(result.tokens);
    defer std.testing.allocator.free(result.ids);
    try std.testing.expectEqual(2, result.tokens.len);
}
