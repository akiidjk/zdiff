const std = @import("std");

const myers = @import("myers.zig");
const token = @import("token.zig");

pub const Side = struct {
    ids: []u32,
    index: []usize,
    changed: []bool,

    fn deinit(self: Side, allocator: std.mem.Allocator) void {
        allocator.free(self.ids);
        allocator.free(self.index);
        allocator.free(self.changed);
    }
};

pub const Discarded = struct {
    old: Side,
    new: Side,

    pub fn deinit(self: Discarded, allocator: std.mem.Allocator) void {
        self.old.deinit(allocator);
        self.new.deinit(allocator);
    }
};

const Mark = enum(u2) { keep, discard, provisional };

pub fn discard_confusing_lines(allocator: std.mem.Allocator, interner: *const token.Interner, oldToken: token.Tokenized, newToken: token.Tokenized) !Discarded {
    // IDs are dense from zero, so a flat count array is enough.
    const old_counts = try countIds(allocator, interner.next_id, oldToken.ids);
    defer allocator.free(old_counts);
    const new_counts = try countIds(allocator, interner.next_id, newToken.ids);
    defer allocator.free(new_counts);

    const old_marks = try markLines(allocator, oldToken.ids, new_counts);
    defer allocator.free(old_marks);
    const new_marks = try markLines(allocator, newToken.ids, old_counts);
    defer allocator.free(new_marks);

    refineRuns(old_marks);
    refineRuns(new_marks);

    const old = try split(allocator, oldToken.ids, old_marks);
    errdefer old.deinit(allocator);
    return .{ .old = old, .new = try split(allocator, newToken.ids, new_marks) };
}

fn countIds(allocator: std.mem.Allocator, id_count: u32, ids: []const u32) ![]usize {
    const counts = try allocator.alloc(usize, id_count);
    @memset(counts, 0);
    for (ids) |id| counts[id] += 1;
    return counts;
}

fn markLines(allocator: std.mem.Allocator, ids: []const u32, other_counts: []const usize) ![]Mark {
    // Lines above this frequency are provisional discards.
    var many: usize = 5;
    var tem = ids.len / 64;
    while (true) {
        tem >>= 2;
        if (tem == 0) break;
        many *= 2;
    }

    const marks = try allocator.alloc(Mark, ids.len);
    for (ids, marks) |id, *mark| {
        const nmatch = other_counts[id];
        mark.* = if (nmatch == 0) .discard else if (nmatch > many) .provisional else .keep;
    }
    return marks;
}

// Keep provisional discards unless they sit inside a run of definite discards.
fn refineRuns(marks: []Mark) void {
    var i: usize = 0;
    while (i < marks.len) : (i += 1) {
        switch (marks[i]) {
            .keep => continue,
            .provisional => {
                marks[i] = .keep;
                continue;
            },
            .discard => {},
        }

        var j = i;
        var provisional: usize = 0;
        while (j < marks.len and marks[j] != .keep) : (j += 1) {
            if (marks[j] == .provisional) provisional += 1;
        }

        while (j > i and marks[j - 1] == .provisional) {
            j -= 1;
            marks[j] = .keep;
            provisional -= 1;
        }

        const run = marks[i..j];

        if (provisional * 4 > run.len) {
            for (run) |*m| {
                if (m.* == .provisional) m.* = .keep;
            }
        } else {
            // Restore provisional runs that meet this length threshold.
            var minimum: usize = 1;
            var t = run.len >> 2;
            while (true) {
                t >>= 2;
                if (t == 0) break;
                minimum <<= 1;
            }
            minimum += 1;

            var consec: usize = 0;
            for (run, 0..) |*m, k| {
                if (m.* != .provisional) {
                    consec = 0;
                    continue;
                }
                consec += 1;
                if (consec == minimum) {
                    for (run[k + 1 - minimum .. k + 1]) |*p| p.* = .keep;
                } else if (consec > minimum) {
                    m.* = .keep;
                }
            }

            // Restore the edges until three definite discards appear in a row,
            // or until the first one is at least eight lines in.
            trimEdge(run, false);
            trimEdge(run, true);
        }

        i += run.len - 1;
    }
}

fn trimEdge(run: []Mark, comptime from_end: bool) void {
    var consec: usize = 0;
    for (0..run.len) |n| {
        const m = &run[if (from_end) run.len - 1 - n else n];
        if (n >= 8 and m.* == .discard) break;
        switch (m.*) {
            .provisional => {
                m.* = .keep;
                consec = 0;
            },
            .keep => consec = 0,
            .discard => consec += 1,
        }
        if (consec == 3) break;
    }
}

fn split(allocator: std.mem.Allocator, ids: []const u32, marks: []const Mark) !Side {
    var kept: std.ArrayList(u32) = .empty;
    defer kept.deinit(allocator);
    var index: std.ArrayList(usize) = .empty;
    defer index.deinit(allocator);
    const changed = try allocator.alloc(bool, ids.len);
    errdefer allocator.free(changed);

    for (ids, marks, changed, 0..) |id, mark, *c, i| {
        c.* = mark != .keep;
        if (mark == .keep) {
            try kept.append(allocator, id);
            try index.append(allocator, i);
        }
    }

    const owned_ids = try kept.toOwnedSlice(allocator);
    errdefer allocator.free(owned_ids);
    return .{ .ids = owned_ids, .index = try index.toOwnedSlice(allocator), .changed = changed };
}

// Map a script for the reduced inputs back to the original inputs.
// This consumes `discarded.*.changed`.
pub fn buildScript(allocator: std.mem.Allocator, discarded: Discarded, reduced: []const myers.Edit) !std.ArrayList(myers.Edit) {
    const old = discarded.old;
    const new = discarded.new;
    for (reduced) |edit| switch (edit.op) {
        .KEEP => {},
        .DELETE => for (old.index[edit.startOld..][0..edit.len]) |i| {
            old.changed[i] = true;
        },
        .INSERT => for (new.index[edit.startNew..][0..edit.len]) |i| {
            new.changed[i] = true;
        },
    };

    var script: std.ArrayList(myers.Edit) = .empty;
    errdefer script.deinit(allocator);

    var x: usize = 0;
    var y: usize = 0;
    while (x < old.changed.len or y < new.changed.len) {
        const ox = x;
        const oy = y;
        while (x < old.changed.len and y < new.changed.len and !old.changed[x] and !new.changed[y]) {
            x += 1;
            y += 1;
        }
        if (x > ox) try script.append(allocator, .{ .op = .KEEP, .startOld = ox, .startNew = oy, .len = x - ox });

        const dx = x;
        while (x < old.changed.len and old.changed[x]) x += 1;
        if (x > dx) try script.append(allocator, .{ .op = .DELETE, .startOld = dx, .startNew = y, .len = x - dx });

        const iy = y;
        while (y < new.changed.len and new.changed[y]) y += 1;
        if (y > iy) try script.append(allocator, .{ .op = .INSERT, .startOld = x, .startNew = iy, .len = y - iy });
    }
    return script;
}

fn expectRoundTrip(old: []const u8, new: []const u8) !void {
    const a = std.testing.allocator;
    var interner: token.Interner = .{};
    defer interner.deinit(a);
    const o = try token.tokenizeBy(a, old, '\n', &interner, false);
    defer a.free(o.tokens);
    defer a.free(o.ids);
    const n = try token.tokenizeBy(a, new, '\n', &interner, false);
    defer a.free(n.tokens);
    defer a.free(n.ids);

    const d = try discard_confusing_lines(a, &interner, o, n);
    defer d.deinit(a);
    var reduced = try myers.diff(u32, a, d.old.ids, d.new.ids, 6500);
    defer reduced.deinit(a);
    var script = try buildScript(a, d, reduced.items);
    defer script.deinit(a);

    const rebuilt = try @import("root.zig").applyScript(u32, a, script.items, o.ids, n.ids);
    defer a.free(rebuilt);
    try std.testing.expectEqualSlices(u32, n.ids, rebuilt);
}

test "lines without a match are discarded and script still rebuilds new" {
    try expectRoundTrip("a\nx\nb\ny\nc\n", "a\nb\nz\nc\n");
    try expectRoundTrip("", "a\nb\n");
    try expectRoundTrip("a\nb\n", "");
}

test "frequent lines inside a run of discards are dropped" {
    // `}` is too common in new, so unique neighbors cause it to be discarded.
    const new = "}\n" ** 10;
    try expectRoundTrip("u1\nu2\nu3\n}\nu4\nu5\nu6\n", new);

    var marks = [_]Mark{ .discard, .discard, .discard, .provisional, .discard, .discard, .discard };
    refineRuns(&marks);
    try std.testing.expectEqual(.provisional, marks[3]);
}

test "provisional lines at run edges are cancelled" {
    var marks = [_]Mark{ .provisional, .discard, .provisional, .keep, .discard, .provisional };
    refineRuns(&marks);
    try std.testing.expectEqualSlices(Mark, &.{ .keep, .discard, .keep, .keep, .discard, .keep }, &marks);
}
