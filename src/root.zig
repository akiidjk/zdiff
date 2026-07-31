const std = @import("std");
const Io = std.Io;

const Frontier = []usize;
const Op = enum {
    KEEP,
    INSERT,
    DELETE,
};
const Edit = struct {
    op: Op,
    oldIndex: ?usize,
    newIndex: ?usize,
};
const Script = std.ArrayList(Edit);
const Trace = std.ArrayList(usize);

// This give only the number of operation and nothing else
pub fn shortestEdit(allocator: std.mem.Allocator, left: []const u8, right: []const u8) !?usize {
    const N = left.len;
    const M = right.len;
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
        while (k <= MAX + d) : (k += 2) {
            if (k == MAX - d or (k != MAX + d and V[k - 1] < V[k + 1])) {
                x = V[k + 1]; //  insert B[y]
            } else {
                x = V[k - 1] + 1; // delete A[x-1]
            }

            y = x + MAX - k;
            while (x < N and y < M and left[x] == right[y]) { // snake
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

// this give the full path of operation
pub fn diff(allocator: std.mem.Allocator, left: []const u8, right: []const u8) !Script {
    const N = left.len;
    const M = right.len;
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
        while (k <= MAX + d) : (k += 2) {
            if (k == MAX - d or (k != MAX + d and V[k - 1] < V[k + 1])) {
                x = V[k + 1]; //  insert B[y]
            } else {
                x = V[k - 1] + 1; // delete A[x-1]
            }

            y = x + MAX - k;
            while (x < N and y < M and left[x] == right[y]) { // snake
                x += 1;
                y += 1;
            }
            V[k] = x;

            if (x >= N and y >= M) return try backtrack(allocator, trace.items, d, MAX, left, right);
        }

        try trace.ensureUnusedCapacity(allocator, d + 1);
        var s: usize = MAX - d;
        while (s <= MAX + d) : (s += 2) trace.appendAssumeCapacity(V[s]);
    }

    return .empty;
}

pub fn backtrack(allocator: std.mem.Allocator, trace: []usize, d: usize, MAX: usize, left: []const u8, right: []const u8) !Script {
    var script: Script = .empty;
    var x: usize = left.len;
    var y: usize = right.len;

    try script.ensureTotalCapacity(allocator, (MAX - d) / 2 + d);

    var k: usize = 0;
    var D: usize = d;
    while (D > 0) : (D -= 1) {
        const V: Frontier = trace;
        _ = V; // autofix
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
            script.appendAssumeCapacity(.{ .op = Op.KEEP, .newIndex = y - 1, .oldIndex = x - 1 });
            x -= 1;
            y -= 1;
        }

        if (x == prev_x) {
            script.appendAssumeCapacity(.{ .op = Op.INSERT, .newIndex = prev_y, .oldIndex = null });
        } else {
            script.appendAssumeCapacity(.{ .op = Op.DELETE, .newIndex = null, .oldIndex = prev_x });
        }
        x = prev_x;
        y = prev_y;
    }

    while (x > 0) {
        script.appendAssumeCapacity(.{ .op = Op.KEEP, .newIndex = y - 1, .oldIndex = x - 1 });
        x -= 1;
        y -= 1;
    }

    std.mem.reverse(Edit, script.items);

    return script;
}

fn applyScript(alloc: std.mem.Allocator, script: []const Edit, left: []const u8, right: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    var i: usize = 0; // cursore su left
    var j: usize = 0; // cursore su right
    for (script) |step| {
        switch (step.op) {
            .INSERT => {
                if (j >= right.len) return error.CursorOverrun;
                try out.append(alloc, right[j]);
                j += 1;
            },
            .DELETE => {
                if (i >= left.len) return error.CursorOverrun;
                i += 1;
            },
            .KEEP => {
                if (i >= left.len or j >= right.len) return error.CursorOverrun;
                if (left[i] != right[j]) return error.KeepMismatch;
                try out.append(alloc, left[i]);
                i += 1;
                j += 1;
            },
        }
    }

    if (i != left.len or j != right.len) return error.IncompleteScript;
    return out.toOwnedSlice(alloc);
}

// function for testing
fn roundTrip(a: []const u8, b: []const u8) !void {
    const alloc = std.testing.allocator;

    const script = try diff(alloc, a, b);
    defer alloc.free(script);

    const rebuilt = try applyScript(alloc, script, a, b);
    defer alloc.free(rebuilt);

    try std.testing.expectEqualSlices(u8, b, rebuilt);
}

test "corpus round-trip" {
    const io = std.testing.io;
    const alloc = std.testing.allocator;
    const cwd = std.Io.Dir.cwd();

    const manifest = try std.Io.Dir.readFileAlloc(cwd, io, "corpus/index.txt", alloc, .unlimited);
    defer alloc.free(manifest);

    var lines = std.mem.tokenizeScalar(u8, manifest, '\n');
    var n: usize = 0;
    while (lines.next()) |line| {
        var cols = std.mem.tokenizeScalar(u8, line, '\t');
        const pa = cols.next() orelse continue;
        const pb = cols.next() orelse continue;

        const a = try std.Io.Dir.readFileAlloc(cwd, io, pa, alloc, .unlimited);
        defer alloc.free(a);

        const b = try std.Io.Dir.readFileAlloc(cwd, io, pb, alloc, .unlimited);
        defer alloc.free(b);

        var script = try diff(alloc, a, b);
        defer script.deinit(alloc);
        const rebuilt = try applyScript(alloc, script.items, a, b);
        defer alloc.free(rebuilt);

        std.testing.expectEqualSlices(u8, b, rebuilt) catch |e| {
            std.debug.print("FAIL su {s}\n", .{pa});
            return e;
        };
        n += 1;
    }
    std.debug.print("{d} coppie ok\n", .{n});
}
