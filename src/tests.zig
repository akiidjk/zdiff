const std = @import("std");

const applyScript = @import("root.zig").applyScript;
const diff = @import("root.zig").diff;
const Edit = @import("root.zig").Edit;
const Op = @import("root.zig").Op;
const shortestEdit = @import("root.zig").shortestEdit;

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

    var script = try diff(alloc, a, b, 6726);
    defer script.deinit(alloc);

    const rebuilt = try applyScript(alloc, script.items, a, b);
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

    const d_ref = (try shortestEdit(std.testing.allocator, a, b, 6726)).?;
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

    var script = try diff(alloc, a, b, 6726);
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
        const d = (try shortestEdit(alloc, c.a, c.b, 6726)).?;
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

        var script = try diff(alloc, a, b, 6726);
        defer script.deinit(alloc);

        std.debug.print(ANSI_BLUE ++ "corpus round-trip: diff produced script.items.len={d}\n" ++ ANSI_RESET, .{script.items.len});

        const rebuilt = try applyScript(alloc, script.items, a, b);
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
