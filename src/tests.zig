const std = @import("std");

const applyScript = @import("root.zig").applyScript;
const diff = @import("root.zig").diff;
const Edit = @import("root.zig").Edit;
const hunk = @import("hunk.zig");
const Op = @import("root.zig").Op;
const shortestEdit = @import("root.zig").shortestEdit;
const token = @import("token.zig");
const unified = @import("unified.zig");

const ExpectedHunk = struct {
    old_start: usize,
    old_len: usize,
    new_start: usize,
    new_len: usize,
    first_run: usize,
    run_count: usize,
};

fn expectHunks(
    script: []const Edit,
    context: usize,
    old_size: usize,
    new_size: usize,
    expected: []const ExpectedHunk,
) !void {
    const alloc = std.testing.allocator;
    const got = try hunk.hunks(alloc, script, old_size, new_size, context);
    defer alloc.free(got);

    std.testing.expectEqual(expected.len, got.len) catch |e| {
        std.debug.print("\nexpectHunks FAIL: attesi {d} hunk, trovati {d}\n", .{ expected.len, got.len });
        for (got, 0..) |x, i| {
            std.debug.print("  [{d}] old={d}+{d} new={d}+{d} runs={d}+{d}\n", .{
                i, x.old_start, x.old_len, x.new_start, x.new_len, x.first_run, x.run_count,
            });
        }
        return e;
    };

    for (expected, got, 0..) |exp, actual, i| {
        if (exp.old_start != actual.old_start or
            exp.old_len != actual.old_len or
            exp.new_start != actual.new_start or
            exp.new_len != actual.new_len or
            exp.first_run != actual.first_run or
            exp.run_count != actual.run_count)
        {
            std.debug.print(
                "\nexpectHunks FAIL a [{d}]\n  atteso: old={d}+{d} new={d}+{d} runs={d}+{d}\n  trovato: old={d}+{d} new={d}+{d} runs={d}+{d}\n",
                .{
                    i,
                    exp.old_start,
                    exp.old_len,
                    exp.new_start,
                    exp.new_len,
                    exp.first_run,
                    exp.run_count,
                    actual.old_start,
                    actual.old_len,
                    actual.new_start,
                    actual.new_len,
                    actual.first_run,
                    actual.run_count,
                },
            );
            return error.HunkMismatch;
        }
    }
}

fn expectHunkInvariants(script: []const Edit, hs: anytype, old_size: usize, new_size: usize) !void {
    var prev_old_end: usize = 0;
    var prev_new_end: usize = 0;

    for (hs, 0..) |x, i| {
        try std.testing.expect(x.old_start <= old_size);
        try std.testing.expect(x.new_start <= new_size);
        try std.testing.expect(x.old_len <= old_size - x.old_start);
        try std.testing.expect(x.new_len <= new_size - x.new_start);
        try std.testing.expect(x.first_run <= script.len);
        try std.testing.expect(x.run_count <= script.len - x.first_run);
        try std.testing.expect(x.run_count > 0);

        var has_change = false;
        for (script[x.first_run .. x.first_run + x.run_count]) |run| {
            if (run.op != .KEEP) has_change = true;
        }
        try std.testing.expect(has_change);

        if (i > 0) {
            try std.testing.expect(prev_old_end <= x.old_start);
            try std.testing.expect(prev_new_end <= x.new_start);
        }
        prev_old_end = x.old_start + x.old_len;
        prev_new_end = x.new_start + x.new_len;
    }
}

const ANSI_RESET = "\x1b[0m";
const ANSI_BOLD = "\x1b[1m";
const ANSI_RED = "\x1b[31m";
const ANSI_GREEN = "\x1b[32m";
const ANSI_YELLOW = "\x1b[33m";
const ANSI_BLUE = "\x1b[34m";
const ANSI_MAGENTA = "\x1b[35m";
const ANSI_CYAN = "\x1b[36m";

fn roundTrip(a: []const u8, b: []const u8) !void {
    const alloc = std.testing.allocator;

    var script = try diff(u8, alloc, a, b, 6726);
    defer script.deinit(alloc);

    const rebuilt = try applyScript(u8, alloc, script.items, a, b);
    defer alloc.free(rebuilt);

    std.testing.expectEqualSlices(u8, b, rebuilt) catch |e| {
        std.debug.print("\nroundTrip FAIL\n  a = \"{s}\"\n  b = \"{s}\"\n", .{ a, b });
        dumpScript(script.items);
        return e;
    };

    try checkInvariants(script.items, a, b);
}

fn checkInvariants(script: []const Edit, a: []const u8, b: []const u8) !void {
    var keep: usize = 0;
    var del: usize = 0;
    var ins: usize = 0;

    for (script) |e| switch (e.op) {
        .KEEP => keep += e.len,
        .DELETE => del += e.len,
        .INSERT => ins += e.len,
    };

    try std.testing.expectEqual(a.len, keep + del);
    try std.testing.expectEqual(b.len, keep + ins);

    const d = del + ins;
    try std.testing.expectEqual(a.len + b.len - 2 * keep, d);

    const d_ref = (try shortestEdit(u8, std.testing.allocator, a, b, 6726)).?;
    try std.testing.expectEqual(d_ref, d);

    try std.testing.expectEqual((a.len + b.len) % 2, d % 2);
    try std.testing.expect(d <= a.len + b.len);
    try std.testing.expect(d >= @max(a.len, b.len) - @min(a.len, b.len));

    for (script, 0..) |e, i| {
        if (e.len == 0) return error.EmptyRun;
        if (i > 0 and script[i - 1].op == e.op) {
            std.debug.print("\nrun adiacenti non fusi a [{d}]: {s} {d} + {s} {d}\n", .{
                i, @tagName(script[i - 1].op), script[i - 1].len, @tagName(e.op), e.len,
            });
            return error.UnmergedRuns;
        }
    }
}

const ExpectedRun = struct { op: Op, len: usize };

fn expectRuns(a: []const u8, b: []const u8, expected: []const ExpectedRun) !void {
    const alloc = std.testing.allocator;

    var script = try diff(u8, alloc, a, b, 6726);
    defer script.deinit(alloc);

    try roundTrip(a, b);

    std.testing.expectEqual(expected.len, script.items.len) catch |e| {
        std.debug.print("\nexpectRuns FAIL (numero di run)\n  a = \"{s}\"\n  b = \"{s}\"\n", .{ a, b });
        dumpScript(script.items);
        return e;
    };

    for (expected, script.items, 0..) |exp, got, i| {
        if (exp.op != got.op or exp.len != got.len) {
            std.debug.print("\nexpectRuns FAIL a [{d}]: atteso {s} {d}, trovato {s} {d}\n", .{
                i, @tagName(exp.op), exp.len, @tagName(got.op), got.len,
            });
            dumpScript(script.items);
            return error.RunMismatch;
        }
    }
}

fn dumpScript(script: []const Edit) void {
    std.debug.print("  script ({d} run):", .{script.len});
    for (script) |e| std.debug.print(" {s}:{d}", .{ @tagName(e.op), e.len });
    std.debug.print("\n", .{});
}

test "degenerate" {
    try roundTrip("", "");
    try expectRuns("a", "", &.{.{ .op = .DELETE, .len = 1 }});
    try expectRuns("", "a", &.{.{ .op = .INSERT, .len = 1 }});
    try expectRuns("aaaaa", "", &.{.{ .op = .DELETE, .len = 5 }});
    try expectRuns("", "bbbbb", &.{.{ .op = .INSERT, .len = 5 }});
    try expectRuns("a", "a", &.{.{ .op = .KEEP, .len = 1 }});
    try expectRuns("abcde", "abcde", &.{.{ .op = .KEEP, .len = 5 }});
}

test "edge transitions" {
    try expectRuns("a", "ab", &.{
        .{ .op = .KEEP, .len = 1 },
        .{ .op = .INSERT, .len = 1 },
    });
    try expectRuns("ab", "a", &.{
        .{ .op = .KEEP, .len = 1 },
        .{ .op = .DELETE, .len = 1 },
    });
    try expectRuns("b", "ab", &.{
        .{ .op = .INSERT, .len = 1 },
        .{ .op = .KEEP, .len = 1 },
    });
    try expectRuns("ab", "b", &.{
        .{ .op = .DELETE, .len = 1 },
        .{ .op = .KEEP, .len = 1 },
    });

    try roundTrip("aX", "aY");
    try roundTrip("Xa", "Ya");
    try roundTrip("aXb", "aYb");
}

test "long runs" {
    try expectRuns("aaaaabbbbb", "aaaaa", &.{
        .{ .op = .KEEP, .len = 5 },
        .{ .op = .DELETE, .len = 5 },
    });
    try expectRuns("aaaaa", "aaaaabbbbb", &.{
        .{ .op = .KEEP, .len = 5 },
        .{ .op = .INSERT, .len = 5 },
    });
    try expectRuns("XXXXXaaaaa", "aaaaa", &.{
        .{ .op = .DELETE, .len = 5 },
        .{ .op = .KEEP, .len = 5 },
    });
    try expectRuns("aaaaa", "XXXXXaaaaa", &.{
        .{ .op = .INSERT, .len = 5 },
        .{ .op = .KEEP, .len = 5 },
    });

    try roundTrip("aaaaaXXXXXbbbbb", "aaaaaYYYYYbbbbb");
    try roundTrip("aaaaaaaaaaXXXXXXXXXX", "XXXXXXXXXXaaaaaaaaaa");
}

test "broken snakes" {
    try roundTrip("aaaaaXaaaaaYaaaaa", "aaaaaaaaaaaaaaa");
    try roundTrip("aaaaaaaaaaaaaaa", "aaaaaXaaaaaYaaaaa");
    try roundTrip("aXbXcXdXeXf", "aYbYcYdYeYf");
    try roundTrip("abcabcabcabc", "abcabcabc");
    try roundTrip("aaaaaXbbbbbYccccc", "aaaaabbbbbccccc");
    try roundTrip("aXaXaXaXaXa", "aaaaaa");
    try roundTrip("aaaaaa", "aXaXaXaXaXa");
    try roundTrip("aaXaaXaaXaa", "aaaaaaaa");
}

test "worst case" {
    try roundTrip("ab", "cd");
    try roundTrip("abc", "xyz");
    try expectRuns("aaaa", "bbbb", &.{
        .{ .op = .DELETE, .len = 4 },
        .{ .op = .INSERT, .len = 4 },
    });
    try roundTrip("aaaaaaaaaa", "bbbbbbbbbb");
    try roundTrip("abcdefgh", "hgfedcba");
}

test "alternation" {
    try roundTrip("ab", "ba");
    try roundTrip("ababab", "bababa");
    try roundTrip("aaaab", "baaaa");
    try roundTrip("abcd", "acbd");
    try roundTrip("abcabba", "cbabac");
    try roundTrip("abcabc", "abc");
    try roundTrip("aaa", "aaaa");
}

test "known distances" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { a: []const u8, b: []const u8, d: usize }{
        .{ .a = "abcabba", .b = "cbabac", .d = 5 },
        .{ .a = "abcd", .b = "acbd", .d = 2 },
        .{ .a = "ab", .b = "ba", .d = 2 },
        .{ .a = "aaa", .b = "aaaa", .d = 1 },
        .{ .a = "abcabc", .b = "abc", .d = 3 },
        .{ .a = "aaaab", .b = "baaaa", .d = 2 },
        .{ .a = "ababab", .b = "bababa", .d = 2 },
        .{ .a = "abc", .b = "xyz", .d = 6 },
        .{ .a = "aaaa", .b = "bbbb", .d = 8 },
    };
    for (cases) |c| {
        const d = (try shortestEdit(u8, alloc, c.a, c.b, 6726)).?;
        std.testing.expectEqual(c.d, d) catch |e| {
            std.debug.print("\ndistanza sbagliata: \"{s}\" -> \"{s}\": atteso {d}, trovato {d}\n", .{ c.a, c.b, c.d, d });
            return e;
        };
    }
}

fn fuzzAlphabet(seed: u64, iterations: usize, alphabet: u8, max_len: usize) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();

    var buf_a: [32]u8 = undefined;
    var buf_b: [32]u8 = undefined;

    for (0..iterations) |it| {
        const n = r.uintLessThan(usize, max_len);
        const m = r.uintLessThan(usize, max_len);
        for (buf_a[0..n]) |*c| c.* = 'a' + r.uintLessThan(u8, alphabet);
        for (buf_b[0..m]) |*c| c.* = 'a' + r.uintLessThan(u8, alphabet);

        roundTrip(buf_a[0..n], buf_b[0..m]) catch |e| {
            std.debug.print("\nfuzz FAIL (seed={x} it={d} alphabet={d})\n", .{ seed, it, alphabet });
            try shrink(buf_a[0..n], buf_b[0..m]);
            return e;
        };
    }
}

test "fuzz alphabet 2" {
    try fuzzAlphabet(0xDEADBEEF, 20_000, 2, 20);
}

test "fuzz alphabet 3" {
    try fuzzAlphabet(0xC0FFEE, 20_000, 3, 24);
}

test "fuzz alphabet 8" {
    try fuzzAlphabet(0xBADF00D, 10_000, 8, 32);
}

fn stillFails(a: []const u8, b: []const u8) bool {
    roundTrip(a, b) catch return true;
    return false;
}

fn shrink(a_in: []const u8, b_in: []const u8) !void {
    const alloc = std.testing.allocator;

    var a = try alloc.dupe(u8, a_in);
    defer alloc.free(a);
    var b = try alloc.dupe(u8, b_in);
    defer alloc.free(b);

    var a_len = a.len;
    var b_len = b.len;

    var changed = true;
    while (changed) {
        changed = false;

        var i: usize = 0;
        while (i < a_len) {
            var tmp: [32]u8 = undefined;
            @memcpy(tmp[0..i], a[0..i]);
            @memcpy(tmp[i .. a_len - 1], a[i + 1 .. a_len]);
            if (stillFails(tmp[0 .. a_len - 1], b[0..b_len])) {
                @memcpy(a[0 .. a_len - 1], tmp[0 .. a_len - 1]);
                a_len -= 1;
                changed = true;
            } else i += 1;
        }

        var j: usize = 0;
        while (j < b_len) {
            var tmp: [32]u8 = undefined;
            @memcpy(tmp[0..j], b[0..j]);
            @memcpy(tmp[j .. b_len - 1], b[j + 1 .. b_len]);
            if (stillFails(a[0..a_len], tmp[0 .. b_len - 1])) {
                @memcpy(b[0 .. b_len - 1], tmp[0 .. b_len - 1]);
                b_len -= 1;
                changed = true;
            } else j += 1;
        }
    }

    std.debug.print("  controesempio minimo:\n    a = \"{s}\"  (len {d})\n    b = \"{s}\"  (len {d})\n", .{
        a[0..a_len], a_len, b[0..b_len], b_len,
    });
}

test "hunks degenerate" {
    try expectHunks(&.{}, 10, 0, 0, &.{});

    const only_keep = [_]Edit{
        .{ .op = .KEEP, .startOld = 0, .startNew = 0, .len = 20 },
    };
    try expectHunks(&only_keep, 10, 20, 20, &.{});
}

test "hunks single delete with context" {
    const script = [_]Edit{
        .{ .op = .KEEP, .startOld = 0, .startNew = 0, .len = 10 },
        .{ .op = .DELETE, .startOld = 10, .startNew = 10, .len = 3 },
        .{ .op = .KEEP, .startOld = 13, .startNew = 10, .len = 17 },
    };

    try expectHunks(&script, 4, 30, 27, &.{.{
        .old_start = 6,
        .old_len = 11,
        .new_start = 6,
        .new_len = 8,
        .first_run = 0,
        .run_count = 3,
    }});
}

test "hunks single insert with context" {
    const script = [_]Edit{
        .{ .op = .KEEP, .startOld = 0, .startNew = 0, .len = 10 },
        .{ .op = .INSERT, .startOld = 10, .startNew = 10, .len = 3 },
        .{ .op = .KEEP, .startOld = 10, .startNew = 13, .len = 17 },
    };

    try expectHunks(&script, 4, 27, 30, &.{.{
        .old_start = 6,
        .old_len = 8,
        .new_start = 6,
        .new_len = 11,
        .first_run = 0,
        .run_count = 3,
    }});
}

test "hunks clamp context at beginning" {
    const script = [_]Edit{
        .{ .op = .DELETE, .startOld = 0, .startNew = 0, .len = 3 },
        .{ .op = .KEEP, .startOld = 3, .startNew = 0, .len = 27 },
    };

    try expectHunks(&script, 4, 30, 27, &.{.{
        .old_start = 0,
        .old_len = 7,
        .new_start = 0,
        .new_len = 4,
        .first_run = 0,
        .run_count = 2,
    }});
}

test "hunks clamp context at end" {
    const script = [_]Edit{
        .{ .op = .KEEP, .startOld = 0, .startNew = 0, .len = 20 },
        .{ .op = .INSERT, .startOld = 20, .startNew = 20, .len = 3 },
    };

    try expectHunks(&script, 4, 20, 23, &.{.{
        .old_start = 16,
        .old_len = 4,
        .new_start = 16,
        .new_len = 7,
        .first_run = 0,
        .run_count = 2,
    }});
}

test "hunks zero context" {
    const script = [_]Edit{
        .{ .op = .KEEP, .startOld = 0, .startNew = 0, .len = 10 },
        .{ .op = .DELETE, .startOld = 10, .startNew = 10, .len = 2 },
        .{ .op = .INSERT, .startOld = 12, .startNew = 10, .len = 3 },
        .{ .op = .KEEP, .startOld = 12, .startNew = 13, .len = 8 },
        .{ .op = .DELETE, .startOld = 20, .startNew = 21, .len = 1 },
    };

    try expectHunks(&script, 0, 21, 21, &.{
        .{
            .old_start = 10,
            .old_len = 2,
            .new_start = 10,
            .new_len = 3,
            .first_run = 1,
            .run_count = 2,
        },
        .{
            .old_start = 20,
            .old_len = 1,
            .new_start = 21,
            .new_len = 0,
            .first_run = 4,
            .run_count = 1,
        },
    });
}

test "hunks keep exactly twice context bridges" {
    const script = [_]Edit{
        .{ .op = .DELETE, .startOld = 10, .startNew = 10, .len = 2 },
        .{ .op = .INSERT, .startOld = 12, .startNew = 10, .len = 3 },
        .{ .op = .KEEP, .startOld = 12, .startNew = 13, .len = 8 },
        .{ .op = .DELETE, .startOld = 20, .startNew = 21, .len = 1 },
        .{ .op = .INSERT, .startOld = 21, .startNew = 21, .len = 1 },
        .{ .op = .KEEP, .startOld = 21, .startNew = 22, .len = 50 },
    };

    try expectHunks(&script, 4, 100, 101, &.{.{
        .old_start = 6,
        .old_len = 19,
        .new_start = 6,
        .new_len = 20,
        .first_run = 0,
        .run_count = 6,
    }});
}

test "hunks keep longer than twice context splits" {
    const script = [_]Edit{
        .{ .op = .DELETE, .startOld = 10, .startNew = 10, .len = 2 },
        .{ .op = .INSERT, .startOld = 12, .startNew = 10, .len = 3 },
        .{ .op = .KEEP, .startOld = 12, .startNew = 13, .len = 9 },
        .{ .op = .DELETE, .startOld = 21, .startNew = 22, .len = 1 },
        .{ .op = .INSERT, .startOld = 22, .startNew = 22, .len = 1 },
        .{ .op = .KEEP, .startOld = 22, .startNew = 23, .len = 50 },
    };

    try expectHunks(&script, 4, 100, 101, &.{
        .{
            .old_start = 6,
            .old_len = 10,
            .new_start = 6,
            .new_len = 11,
            .first_run = 0,
            .run_count = 3,
        },
        .{
            .old_start = 17,
            .old_len = 9,
            .new_start = 18,
            .new_len = 9,
            .first_run = 2,
            .run_count = 4,
        },
    });
}

test "hunks multiple small bridges form one group" {
    const script = [_]Edit{
        .{ .op = .INSERT, .startOld = 10, .startNew = 10, .len = 2 },
        .{ .op = .DELETE, .startOld = 10, .startNew = 12, .len = 1 },
        .{ .op = .KEEP, .startOld = 11, .startNew = 12, .len = 3 },
        .{ .op = .INSERT, .startOld = 14, .startNew = 15, .len = 1 },
        .{ .op = .DELETE, .startOld = 14, .startNew = 16, .len = 2 },
        .{ .op = .KEEP, .startOld = 16, .startNew = 16, .len = 7 },
        .{ .op = .INSERT, .startOld = 23, .startNew = 23, .len = 2 },
        .{ .op = .DELETE, .startOld = 23, .startNew = 25, .len = 1 },
        .{ .op = .KEEP, .startOld = 24, .startNew = 25, .len = 30 },
    };

    try expectHunks(&script, 4, 100, 101, &.{.{
        .old_start = 6,
        .old_len = 22,
        .new_start = 6,
        .new_len = 23,
        .first_run = 0,
        .run_count = 9,
    }});
}

test "hunks end-to-end identical inputs produce no hunks" {
    const alloc = std.testing.allocator;
    const text = "nothing changed here";

    var script = try diff(u8, alloc, text, text, 6726);
    defer script.deinit(alloc);

    const hs = try hunk.hunks(alloc, script.items, text.len, text.len, 8);
    defer alloc.free(hs);

    try std.testing.expectEqual(@as(usize, 0), hs.len);
}

test "corpus round-trip" {
    const io = std.testing.io;
    const alloc = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();

    std.debug.print(ANSI_CYAN ++ "corpus round-trip: starting, reading manifest 'corpus/index.txt'\n" ++ ANSI_RESET, .{});
    std.debug.print(ANSI_CYAN ++ "corpus round-trip: reading file 'corpus/index.txt'\n" ++ ANSI_RESET, .{});

    const manifest = try std.Io.Dir.readFileAlloc(cwd, io, "corpus/index.txt", alloc, .unlimited);
    defer alloc.free(manifest);

    std.debug.print(ANSI_CYAN ++ "corpus round-trip: manifest read, {d} bytes\n" ++ ANSI_RESET, .{manifest.len});

    var lines = std.mem.tokenizeScalar(u8, manifest, '\n');
    var n: usize = 0;
    var lineNo: usize = 0;
    while (lines.next()) |line| {
        lineNo += 1;
        var cols = std.mem.tokenizeScalar(u8, line, '\t');
        const pa = cols.next() orelse {
            std.debug.print(ANSI_YELLOW ++ "corpus round-trip: line {d} skipped (missing column A): '{s}'\n" ++ ANSI_RESET, .{ lineNo, line });
            continue;
        };
        const pb = cols.next() orelse {
            std.debug.print(ANSI_YELLOW ++ "corpus round-trip: line {d} skipped (missing column B): '{s}'\n" ++ ANSI_RESET, .{ lineNo, line });
            continue;
        };

        std.debug.print(ANSI_BLUE ++ "corpus round-trip: line {d}: pa='{s}' pb='{s}'\n" ++ ANSI_RESET, .{ lineNo, pa, pb });
        std.debug.print(ANSI_CYAN ++ "corpus round-trip: reading file '{s}'\n" ++ ANSI_RESET, .{pa});

        const a = try std.Io.Dir.readFileAlloc(cwd, io, pa, alloc, .unlimited);
        defer alloc.free(a);

        const b = try std.Io.Dir.readFileAlloc(cwd, io, pb, alloc, .unlimited);
        defer alloc.free(b);

        std.debug.print(ANSI_BLUE ++ "corpus round-trip: read a.len={d} b.len={d}\n" ++ ANSI_RESET, .{ a.len, b.len });

        var script = try diff(u8, alloc, a, b, 6726);
        defer script.deinit(alloc);

        std.debug.print(ANSI_BLUE ++ "corpus round-trip: diff produced script.items.len={d}\n" ++ ANSI_RESET, .{script.items.len});

        const rebuilt = try applyScript(u8, alloc, script.items, a, b);
        defer alloc.free(rebuilt);

        std.debug.print(ANSI_BLUE ++ "corpus round-trip: rebuilt.len={d} (expected b.len={d})\n" ++ ANSI_RESET, .{ rebuilt.len, b.len });

        std.testing.expectEqualSlices(u8, b, rebuilt) catch |e| {
            std.debug.print(ANSI_RED ++ ANSI_BOLD ++ "FAIL su {s} (pb={s}): error={s}\n" ++ ANSI_RESET, .{ pa, pb, @errorName(e) });
            std.debug.print(ANSI_RED ++ "FAIL details: a.len={d} b.len={d} rebuilt.len={d}\n" ++ ANSI_RESET, .{ a.len, b.len, rebuilt.len });
            return e;
        };
        n += 1;
    }
    std.debug.print(ANSI_GREEN ++ ANSI_BOLD ++ "{d} coppie ok\n" ++ ANSI_RESET, .{n});
}

fn expectTokens(text: []const u8, sep: u8, expected_segments: []const []const u8) !void {
    const alloc = std.testing.allocator;
    var internMap: std.array_hash_map.String(usize) = .empty;
    defer internMap.deinit(alloc);

    const result = try token.tokenizeBy(alloc, text, sep, &internMap);
    defer alloc.free(result.tokens);
    defer alloc.free(result.ids);

    std.testing.expectEqual(expected_segments.len, result.tokens.len) catch |e| {
        std.debug.print("\nexpectTokens FAIL: attesi {d} token, trovati {d}\n", .{ expected_segments.len, result.tokens.len });
        return e;
    };

    var pos: usize = 0;
    for (result.tokens, expected_segments, 0..) |tok, expected, i| {
        try std.testing.expectEqual(pos, tok.start);
        const trimmed = std.mem.trim(u8, text[tok.start .. tok.start + tok.len], &.{sep});
        std.testing.expectEqualStrings(expected, trimmed) catch |e| {
            std.debug.print("\nexpectTokens FAIL a [{d}]: atteso \"{s}\", trovato \"{s}\"\n", .{ i, expected, trimmed });
            return e;
        };
        pos += tok.len;
    }

    try std.testing.expectEqual(text.len, pos);
}

test "tokenize basic split" {
    try expectTokens("a\nb\nc", '\n', &.{ "a", "b", "c" });
}

test "tokenize no separator present" {
    try expectTokens("hello", '\n', &.{"hello"});
}

test "tokenize empty text" {
    try expectTokens("", '\n', &.{""});
}

test "tokenize trailing separator" {
    try expectTokens("a\nb\n", '\n', &.{ "a", "b", "" });
}

test "tokenize interning reuses ids for repeated segments" {
    const alloc = std.testing.allocator;
    var internMap: std.array_hash_map.String(usize) = .empty;
    defer internMap.deinit(alloc);

    const result = try token.tokenizeBy(alloc, "a\nx\nb\nx", '\n', &internMap);
    defer alloc.free(result.tokens);
    defer alloc.free(result.ids);

    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 1 }, result.ids);
}

test "tokenize shared intern map across calls" {
    const alloc = std.testing.allocator;
    var internMap: std.array_hash_map.String(usize) = .empty;
    defer internMap.deinit(alloc);

    const old = try token.tokenizeBy(alloc, "a\nb\nc", '\n', &internMap);
    defer alloc.free(old.tokens);
    defer alloc.free(old.ids);

    const new = try token.tokenizeBy(alloc, "a\nX\nc", '\n', &internMap);
    defer alloc.free(new.tokens);
    defer alloc.free(new.ids);

    try std.testing.expectEqual(old.ids[0], new.ids[0]); // "a" invariato -> stesso id
    try std.testing.expectEqual(old.ids[2], new.ids[2]); // "\nc" invariato -> stesso id
    try std.testing.expect(old.ids[1] != new.ids[1]); // "\nb" vs "\nX" -> id diversi
}

test "viewHex smoke" {
    const alloc = std.testing.allocator;
    const a = "hello world";
    const b = "hello there";

    var script = try diff(u8, alloc, a, b, 6726);
    defer script.deinit(alloc);

    const hs = try hunk.hunks(alloc, script.items, a.len, b.len, 2);
    defer alloc.free(hs);

    try unified.viewHex(a, b, script.items, hs);
}

test "viewToken smoke" {
    const alloc = std.testing.allocator;
    const a = "line one\nline two\nline three";
    const b = "line one\nline TWO\nline three";

    var internMap: std.array_hash_map.String(usize) = .empty;
    defer internMap.deinit(alloc);

    const oldT = try token.tokenizeBy(alloc, a, '\n', &internMap);
    defer alloc.free(oldT.tokens);
    defer alloc.free(oldT.ids);

    const newT = try token.tokenizeBy(alloc, b, '\n', &internMap);
    defer alloc.free(newT.tokens);
    defer alloc.free(newT.ids);

    var script = try diff(usize, alloc, oldT.ids, newT.ids, 6726);
    defer script.deinit(alloc);

    const hs = try hunk.hunks(alloc, script.items, oldT.tokens.len, newT.tokens.len, 1);
    defer alloc.free(hs);

    try unified.viewToken(oldT.tokens, newT.tokens, script.items, hs, a, b);
}
