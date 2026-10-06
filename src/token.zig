const std = @import("std");

pub const Token = struct {
    start: usize,
    len: usize,
};

pub const Tokenized = struct {
    tokens: []Token,
    ids: []u32,
};

pub const CommonTrim = struct {
    old: []const u8,
    new: []const u8,
    line_offset: usize,
    old_incomplete: bool,
    new_incomplete: bool,
    identical: bool,
};

pub const Interner = struct {
    lines: std.array_hash_map.String(u32) = .empty,
    incomplete: ?struct {
        key: []const u8,
        id: u32,
    } = null,
    incomplete_seen: u2 = 0,
    next_id: u32 = 0,

    pub fn deinit(self: *Interner, allocator: std.mem.Allocator) void {
        self.lines.deinit(allocator);
    }

    fn freshId(self: *Interner) u32 {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    fn intern(self: *Interner, allocator: std.mem.Allocator, key: []const u8) !u32 {
        const gop = try self.lines.getOrPut(allocator, key);
        if (!gop.found_existing) gop.value_ptr.* = self.freshId();
        return gop.value_ptr.*;
    }

    fn internIncomplete(self: *Interner, key: []const u8) u32 {
        std.debug.assert(self.incomplete_seen < 2);
        self.incomplete_seen += 1;

        if (self.incomplete) |seen| {
            return if (std.mem.eql(u8, seen.key, key)) seen.id else self.freshId();
        }
        const id = self.freshId();
        self.incomplete = .{ .key = key, .id = id };
        return id;
    }
};

fn lastLineIncomplete(text: []const u8, slice_end: usize, separator: u8) bool {
    return text.len > 0 and text[text.len - 1] != separator and slice_end == text.len;
}

fn estimateLineCount(text: []const u8, separator: u8) usize {
    if (text.len == 0) return 0;

    const sample_len = @min(text.len, 64 * 1024);
    const separator_count = std.mem.count(u8, text[0..sample_len], &.{separator});

    if (sample_len == text.len)
        return separator_count + 1; // The exact line count is known.

    if (separator_count == 0)
        return 16; // No sample, so start small.

    const estimate = text.len * separator_count / sample_len + 1;

    return estimate + estimate / 8; // Leave 12.5% headroom.
}

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
    const old_end = @max(start, suffixEnd(old, suffix, separator, context));
    const new_end = @max(start, suffixEnd(new, suffix, separator, context));
    return .{
        .old = old[start..old_end],
        .new = new[start..new_end],
        .line_offset = line_offset,
        .old_incomplete = start < old_end and lastLineIncomplete(old, old_end, separator),
        .new_incomplete = start < new_end and lastLineIncomplete(new, new_end, separator),
        .identical = prefix == old.len and old.len == new.len,
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

pub fn tokenizeBy(
    allocator: std.mem.Allocator,
    text: []const u8,
    separator: u8,
    interner: *Interner,
    last_incomplete: bool,
) !Tokenized {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    var ids: std.ArrayList(u32) = .empty;
    errdefer ids.deinit(allocator);

    const estimatedLine = estimateLineCount(text, separator);
    try tokens.ensureTotalCapacity(allocator, estimatedLine);
    try ids.ensureTotalCapacity(allocator, estimatedLine);

    var start: usize = 0;
    while (std.mem.findScalarPos(u8, text, start, separator)) |index| {
        try tokens.append(allocator, .{ .start = start, .len = index - start });
        try ids.append(allocator, try interner.intern(allocator, text[start..index]));
        start = index + 1;
    }

    if (start < text.len) {
        try tokens.append(allocator, .{ .start = start, .len = text.len - start });
        const key = text[start..];
        const id = if (last_incomplete) interner.internIncomplete(key) else try interner.intern(allocator, key);
        try ids.append(allocator, id);
    }

    return .{
        .ids = try ids.toOwnedSlice(allocator),
        .tokens = try tokens.toOwnedSlice(allocator),
    };
}

test "tokenizeBy does not invent a line after trailing separator" {
    var intern: Interner = .{};
    defer intern.deinit(std.testing.allocator);
    const result = try tokenizeBy(std.testing.allocator, "one\ntwo\n", '\n', &intern, false);
    defer std.testing.allocator.free(result.tokens);
    defer std.testing.allocator.free(result.ids);
    try std.testing.expectEqual(2, result.tokens.len);
}

fn expectLastIds(old: []const u8, new: []const u8, expect_equal: bool) !void {
    const a = std.testing.allocator;
    var intern: Interner = .{};
    defer intern.deinit(a);
    const t = trimCommon(old, new, '\n', 1);
    const o = try tokenizeBy(a, t.old, '\n', &intern, t.old_incomplete);
    defer a.free(o.tokens);
    defer a.free(o.ids);
    const n = try tokenizeBy(a, t.new, '\n', &intern, t.new_incomplete);
    defer a.free(n.tokens);
    defer a.free(n.ids);
    try std.testing.expectEqual(expect_equal, o.ids[o.ids.len - 1] == n.ids[n.ids.len - 1]);
}

test "incomplete last line differs from complete one" {
    try expectLastIds("a\nx\n", "a\nx", false);
    try expectLastIds("a\nx", "a\nx\n", false);
}

test "two incomplete last lines with same text are equal" {
    try expectLastIds("a\nold\nx", "a\nnew\nx", true);
}

test "line cut by trimCommon is not incomplete" {
    const t = trimCommon("a\nb\nold\nc\nd\n", "a\nb\nnew\nc\nd\n", '\n', 1);
    try std.testing.expect(!t.old_incomplete and !t.new_incomplete);
}

test "empty vs incomplete" {
    const t = trimCommon("", "foo", '\n', 1);
    try std.testing.expect(!t.old_incomplete and t.new_incomplete);
}

test "two incomplete last lines with different text differ" {
    try expectLastIds("a\nold\nx", "a\nnew\ny", false);
}

test "incomplete line never collides with a complete line id" {
    // A complete `x` and an incomplete `x` need different IDs. The incomplete
    // one must not reuse an ID from `lines`.
    const a = std.testing.allocator;
    var intern: Interner = .{};
    defer intern.deinit(a);
    const o = try tokenizeBy(a, "x\ny\n", '\n', &intern, false);
    defer a.free(o.tokens);
    defer a.free(o.ids);
    const n = try tokenizeBy(a, "y\nx", '\n', &intern, true);
    defer a.free(n.tokens);
    defer a.free(n.ids);
    for (o.ids) |id| try std.testing.expect(id != n.ids[1]);
    try std.testing.expectEqual(o.ids[1], n.ids[0]);
}
