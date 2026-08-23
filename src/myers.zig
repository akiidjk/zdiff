const std = @import("std");
const Io = std.Io;

const Frontier = []usize;
pub const Op = enum {
    KEEP,
    INSERT,
    DELETE,
};
pub const Edit = struct {
    op: Op,
    startNew: usize,
    startOld: usize,
    len: usize,
};
const Script = std.ArrayList(Edit);
const Trace = std.ArrayList(usize);

pub fn shortestEdit(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize) !?usize {
    const pre = getLenghtCommonprefix(T, old, new);
    const suf = getLenghtCommonsuffix(T, old[pre..], new[pre..]);
    return try shortestEditRaw(T, allocator, old[pre .. old.len - suf], new[pre .. new.len - suf], max_d);
}

// This give only the number of operation and nothing else
pub fn shortestEditRaw(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize) !?usize {
    const N = old.len;
    const M = new.len;
    const MAX = N + M;
    if (MAX == 0) return 0;
    const V: Frontier = try allocator.alloc(usize, 2 * MAX + 1);
    defer allocator.free(V);
    V[MAX + 1] = 0;

    var k: usize = 0;
    var d: usize = 0;
    var x: usize = 0;
    var y: usize = 0;

    while (d <= MAX) : (d += 1) {
        k = MAX - d;

        if (d > max_d) {
            return error.TooDifferent;
        }
        while (k <= MAX + d) : (k += 2) {
            if (k == MAX - d or (k != MAX + d and V[k - 1] < V[k + 1])) {
                x = V[k + 1]; //  insert B[y]
            } else {
                x = V[k - 1] + 1; // delete A[x-1]
            }

            y = x + MAX - k;
            while (x < N and y < M and old[x] == new[y]) { // snake
                x += 1;
                y += 1;
            }
            V[k] = x;

            if (x >= N and y >= M) return d;
        }
    }

    return null;
}

inline fn traceAt(trace: []const usize, d: usize, i: usize, MAX: usize) usize {
    std.debug.assert(i >= MAX - d and i <= MAX + d);
    return trace[d * (d + 1) / 2 + (i - (MAX - d)) / 2];
}

pub fn getLenghtCommonprefix(comptime T: type, old: []const T, new: []const T) usize {
    var c: usize = 0;
    const len: usize = @min(old.len, new.len);
    for (0..len) |i| {
        if (old[i] == new[i]) {
            c += 1;
        } else {
            return c;
        }
    }
    return c;
}

pub fn getLenghtCommonsuffix(comptime T: type, old: []const T, new: []const T) usize {
    const len = @min(old.len, new.len);
    var c: usize = 0;
    while (c < len and old[old.len - 1 - c] == new[new.len - 1 - c]) c += 1;
    return c;
}

fn addRun(alloc: std.mem.Allocator, pre: usize, suf: usize, inner: Script) !Script {
    var fixedInner: Script = .empty;
    errdefer fixedInner.deinit(alloc);

    try fixedInner.ensureUnusedCapacity(alloc, inner.items.len + 2);

    if (pre == 0 and suf == 0) {
        fixedInner.appendSliceAssumeCapacity(inner.items);
        return fixedInner;
    }

    if (inner.items.len == 0 and (pre != 0 or suf != 0)) {
        fixedInner.appendAssumeCapacity(.{ .op = Op.KEEP, .len = pre + suf, .startNew = 0, .startOld = 0 });
        return fixedInner;
    }

    if (pre != 0) {
        const first = inner.items[0];
        if (first.op == Op.KEEP) {
            fixedInner.appendAssumeCapacity(.{ .op = Op.KEEP, .len = first.len + pre, .startNew = 0, .startOld = 0 });
            fixedInner.appendSliceAssumeCapacity(inner.items[1..]);
        } else {
            fixedInner.appendAssumeCapacity(.{ .op = Op.KEEP, .len = pre, .startNew = 0, .startOld = 0 });
            fixedInner.appendSliceAssumeCapacity(inner.items);
        }
    } else {
        fixedInner.appendSliceAssumeCapacity(inner.items);
    }

    if (suf != 0) {
        const last = inner.getLast();
        if (last.op == Op.KEEP) {
            const lastFixed = &fixedInner.items[fixedInner.items.len - 1];
            lastFixed.len += suf;
        } else {
            var so = last.startOld;
            var sn = last.startNew;
            switch (last.op) {
                .DELETE => so += last.len,
                .INSERT => sn += last.len,
                .KEEP => unreachable,
            }
            fixedInner.appendAssumeCapacity(.{
                .op = Op.KEEP,
                .len = suf,
                .startOld = so,
                .startNew = sn,
            });
        }
    }

    return fixedInner;
}

fn runDiffRaw(comptime T: type, comptime debug: bool, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize, io: if (debug) std.Io else void) !Script {
    if (!debug) return diffRaw(T, allocator, old, new, max_d);

    const start = std.Io.Clock.now(.awake, io);
    const result = try diffRaw(T, allocator, old, new, max_d);
    const end = std.Io.Clock.now(.awake, io);
    std.debug.print("[timing] diffRaw={d} ns\n", .{start.durationTo(end).toNanoseconds()});
    return result;
}

fn myersImpl(comptime T: type, comptime debug: bool, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize, io: if (debug) std.Io else void) !Script {
    const pre = blk: {
        if (debug) {
            const start = std.Io.Clock.now(.awake, io);
            const value = getLenghtCommonprefix(T, old, new);
            const end = std.Io.Clock.now(.awake, io);
            std.debug.print("[timing] prefix={d} ns\n", .{start.durationTo(end).toNanoseconds()});
            break :blk value;
        }
        break :blk getLenghtCommonprefix(T, old, new);
    };
    const suf = blk: {
        if (debug) {
            const start = std.Io.Clock.now(.awake, io);
            const value = getLenghtCommonsuffix(T, old[pre..], new[pre..]);
            const end = std.Io.Clock.now(.awake, io);
            std.debug.print("[timing] suffix={d} ns\n", .{start.durationTo(end).toNanoseconds()});
            break :blk value;
        }
        break :blk getLenghtCommonsuffix(T, old[pre..], new[pre..]);
    };

    var inner = try runDiffRaw(T, debug, allocator, old[pre .. old.len - suf], new[pre .. new.len - suf], max_d, io);

    defer inner.deinit(allocator);
    for (inner.items) |*item| {
        item.startNew += pre;
        item.startOld += pre;
    }

    return try addRun(allocator, pre, suf, inner);
}

// is diffRaw but trimmed
pub fn myers(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize) !Script {
    return myersImpl(T, false, allocator, old, new, max_d, {});
}

pub fn myersDebug(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize, io: std.Io) !Script {
    return myersImpl(T, true, allocator, old, new, max_d, io);
}

pub fn diffRawDebug(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize, io: std.Io) !Script {
    return runDiffRaw(T, true, allocator, old, new, max_d, io);
}

// this give the full path of operation
pub fn diffRaw(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize) !Script {
    const N = old.len;
    const M = new.len;
    const MAX = N + M;

    const V: Frontier = try allocator.alloc(usize, 2 * MAX + 2);
    defer allocator.free(V);
    V[MAX + 1] = 0;

    var trace: Trace = .empty;
    defer trace.deinit(allocator);

    var d: usize = 0;
    var k: usize = 0;
    var x: usize = 0;
    var y: usize = 0;
    while (d <= MAX) : (d += 1) {
        k = MAX - d;

        if (d > max_d) {
            return error.TooDifferent;
        }

        while (k <= MAX + d) : (k += 2) {
            if (k == MAX - d or (k != MAX + d and V[k - 1] < V[k + 1])) {
                x = V[k + 1]; //  insert B[y]
            } else {
                x = V[k - 1] + 1; // delete A[x-1]
            }

            y = x + MAX - k;
            while (x < N and y < M and old[x] == new[y]) { // snake
                x += 1;
                y += 1;
            }
            V[k] = x;

            if (x >= N and y >= M) return try backtrack(allocator, trace.items, d, MAX, old.len, new.len);
        }

        try trace.ensureUnusedCapacity(allocator, d + 1);
        var s: usize = MAX - d;
        while (s <= MAX + d) : (s += 2) trace.appendAssumeCapacity(V[s]);
    }

    return .empty;
}

pub fn backtrack(allocator: std.mem.Allocator, trace: []usize, d: usize, MAX: usize, oldLen: usize, newLen: usize) !Script {
    var script: Script = .empty;
    var x: usize = oldLen;
    var y: usize = newLen;
    var currentOp: Op = .KEEP;
    var counter: usize = 0;

    try script.ensureTotalCapacity(allocator, (MAX - d) / 2 + d);

    var k: usize = 0;
    var D: usize = d;
    while (D > 0) : (D -= 1) {
        k = x + MAX - y;
        var prev_k: usize = 0;
        const p = D - 1;

        if (k == MAX - D or (k != MAX + D and traceAt(trace, p, k - 1, MAX) < traceAt(trace, p, k + 1, MAX))) {
            prev_k = k + 1;
        } else {
            prev_k = k - 1;
        }
        const prev_x: usize = traceAt(trace, p, prev_k, MAX);
        const prev_y: usize = (prev_x + MAX) - prev_k;

        while (x > prev_x and y > prev_y) {
            if (currentOp == Op.KEEP) {
                counter += 1;
            } else {
                if (counter > 0) script.appendAssumeCapacity(.{ .op = currentOp, .len = counter, .startNew = y, .startOld = x });
                currentOp = Op.KEEP;
                counter = 1;
            }
            x -= 1;
            y -= 1;
        }

        if (x == prev_x) {
            if (currentOp == Op.INSERT) { // Accumulo perche currentOp e' uguale alla run
                counter += 1;
            } else { // OP CHANGE
                if (counter > 0) script.appendAssumeCapacity(.{ .op = currentOp, .len = counter, .startNew = y, .startOld = x });
                currentOp = Op.INSERT;
                counter = 1;
            }
        } else {
            if (currentOp == Op.DELETE) {
                counter += 1;
            } else { // OP CHANGE
                if (counter > 0) script.appendAssumeCapacity(.{ .op = currentOp, .len = counter, .startNew = y, .startOld = x });
                currentOp = Op.DELETE;
                counter = 1;
            }
        }

        x = prev_x;
        y = prev_y;
    }

    while (x > 0) {
        if (currentOp == Op.KEEP) {
            counter += 1;
        } else {
            if (counter > 0) script.appendAssumeCapacity(.{ .op = currentOp, .len = counter, .startNew = y, .startOld = x });
            currentOp = Op.KEEP;
            counter = 1;
        }
        x -= 1;
        y -= 1;
    }

    if (counter > 0) {
        script.appendAssumeCapacity(.{ .op = currentOp, .len = counter, .startNew = y, .startOld = x });
    }

    std.mem.reverse(Edit, script.items);

    return script;
}
