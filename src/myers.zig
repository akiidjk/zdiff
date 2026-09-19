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

// ============================== ShortestEdit ==================================

// This get the shortestEdit path with standard implementation and trimmed input
pub fn shortestEdit(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize) !?usize {
    const pre = getLengthCommonPrefix(T, old, new);
    const suf = getLengthCommonSuffix(T, old[pre..], new[pre..]);
    return try shortestEditRaw(T, allocator, old[pre .. old.len - suf], new[pre .. new.len - suf], max_d);
}

// This give only the number of operation and nothing else without trimming
pub fn shortestEditRaw(comptime T: type, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize) !?usize {
    const N = old.len;
    const M = new.len;
    const offset = N + M;
    if (offset == 0) return 0;
    const V: Frontier = try allocator.alloc(usize, 2 * offset + 1);
    defer allocator.free(V);
    V[offset + 1] = 0;

    var k: usize = 0;
    var d: usize = 0;
    var x: usize = 0;
    var y: usize = 0;

    while (d <= offset) : (d += 1) {
        k = offset - d;

        if (d > max_d) {
            return error.TooDifferent;
        }
        while (k <= offset + d) : (k += 2) {
            if (k == offset - d or (k != offset + d and V[k - 1] < V[k + 1])) {
                x = V[k + 1]; //  insert B[y]
            } else {
                x = V[k - 1] + 1; // devare A[x-1]
            }

            y = x + offset - k;
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

// ============================ PRELIMINARY OPERATION  ===========================

// Get the length of common prefix with SIMD and @Vector
pub fn getLengthCommonPrefix(comptime T: type, old: []const T, new: []const T) usize {
    const len = @min(old.len, new.len);

    const VecLen = 32;
    const Vec = @Vector(VecLen, T);

    var i: usize = 0;

    while (i + VecLen <= len) : (i += VecLen) {
        const a: Vec = old[i..][0..VecLen].*;
        const b: Vec = new[i..][0..VecLen].*;

        const eq = a == b;

        if (!@reduce(.And, eq)) {
            var j: usize = 0;
            while (j < VecLen) : (j += 1) {
                if (old[i + j] != new[i + j])
                    return i + j;
            }

            unreachable;
        }
    }

    while (i < len) : (i += 1) {
        if (old[i] != new[i])
            return i;
    }

    return len;
}

// Get the length of common suffix with SIMD and @Vector
pub fn getLengthCommonSuffix(comptime T: type, old: []const T, new: []const T) usize {
    const len = @min(old.len, new.len);

    const VecLen = 32;
    const Vec = @Vector(VecLen, T);

    var c: usize = 0;

    while (c + VecLen <= len) {
        const old_start = old.len - c - VecLen;
        const new_start = new.len - c - VecLen;

        const a: Vec = old[old_start..][0..VecLen].*;
        const b: Vec = new[new_start..][0..VecLen].*;

        const eq = a == b;

        if (!@reduce(.And, eq)) {
            var j: usize = 0;

            while (j < VecLen) : (j += 1) {
                const offset = j + 1;

                if (old[old.len - c - offset] !=
                    new[new.len - c - offset])
                {
                    return c + j;
                }
            }

            unreachable;
        }

        c += VecLen;
    }

    while (c < len and
        old[old.len - 1 - c] == new[new.len - 1 - c])
    {
        c += 1;
    }

    return c;
}

// This add the missing Edit to the script from the trimming done before
fn addEdit(alloc: std.mem.Allocator, pre: usize, suf: usize, inner: Script) !Script {
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

// Run diffRaw but with debug flag distinct
pub fn runDiffRaw(comptime T: type, comptime debug: bool, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize, io: if (debug) std.Io else void) !Script {
    if (!debug) return diff(T, allocator, old, new, max_d);

    const start = std.Io.Clock.now(.awake, io);
    const result = try diff(T, allocator, old, new, max_d);
    const end = std.Io.Clock.now(.awake, io);
    std.debug.print("[timing] diffRaw={d} ns\n", .{start.durationTo(end).toNanoseconds()});
    return result;
}

// Myers algoritm but with trimming
pub fn myersWTrimming(comptime T: type, comptime debug: bool, allocator: std.mem.Allocator, old: []const T, new: []const T, max_d: usize, io: if (debug) std.Io else void) !Script {
    const pre = blk: {
        if (debug) {
            const start = std.Io.Clock.now(.awake, io);
            const value = getLengthCommonPrefix(T, old, new);
            const end = std.Io.Clock.now(.awake, io);
            std.debug.print("[timing] prefix={d} ns\n", .{start.durationTo(end).toNanoseconds()});
            break :blk value;
        }
        break :blk getLengthCommonPrefix(T, old, new);
    };
    const suf = blk: {
        if (debug) {
            const start = std.Io.Clock.now(.awake, io);
            const value = getLengthCommonSuffix(T, old[pre..], new[pre..]);
            const end = std.Io.Clock.now(.awake, io);
            std.debug.print("[timing] suffix={d} ns\n", .{start.durationTo(end).toNanoseconds()});
            break :blk value;
        }
        break :blk getLengthCommonSuffix(T, old[pre..], new[pre..]);
    };

    var inner = try runDiffRaw(T, debug, allocator, old[pre .. old.len - suf], new[pre .. new.len - suf], max_d, io);

    defer inner.deinit(allocator);
    for (inner.items) |*item| {
        item.startNew += pre;
        item.startOld += pre;
    }

    return try addEdit(allocator, pre, suf, inner);
}

// =========================== MAIN ALGO ===================================

const Point = struct { usize, usize };

const Snake = struct {
    start: Point,
    end: Point,
};

const Box = struct {
    left: usize,
    right: usize,
    top: usize,
    bottom: usize,

    fn width(self: *const Box) usize {
        return self.right - self.left;
    }

    fn height(self: *const Box) usize {
        return self.bottom - self.top;
    }

    fn size(self: *const Box) usize {
        return self.width() + self.height();
    }

    fn delta(self: *const Box) isize {
        const w: isize = @as(isize, @intCast(self.width()));
        const h: isize = @as(isize, @intCast(self.height()));
        return w - h;
    }
};

fn appendPoint(points: []Point, used: *usize, point: Point) void {
    std.debug.assert(used.* < points.len);

    points[used.*] = point;
    used.* += 1;
}

fn appendEdit(script: *Script, op: Op, x: usize, y: usize) void {
    if (script.items.len > 0 and script.items[script.items.len - 1].op == op) {
        script.items[script.items.len - 1].len += 1;
    } else {
        script.appendAssumeCapacity(.{ .op = op, .len = 1, .startNew = y, .startOld = x });
    }
}

fn findPath(
    comptime T: type,
    allocator: std.mem.Allocator,
    snake_points: []Point,
    workspace: []isize,
    used: *usize,
    left: usize,
    top: usize,
    right: usize,
    bottom: usize,
    old: []const T,
    new: []const T,
) !void {
    const box = Box{ .left = left, .right = right, .top = top, .bottom = bottom };

    if (box.width() == 0) {
        appendPoint(snake_points, used, .{ box.left, box.top });

        var y = box.top;
        while (y < box.bottom) {
            y += 1;
            appendPoint(snake_points, used, .{ box.left, y });
        }

        return;
    }

    if (box.height() == 0) {
        appendPoint(snake_points, used, .{ box.left, box.top });

        var x = box.left;
        while (x < box.right) {
            x += 1;
            appendPoint(snake_points, used, .{ x, box.top });
        }

        return;
    }

    const snake = try findMidpoint(T, workspace, box, old, new) orelse return;

    const start = snake.start;
    const end = snake.end;

    const head_before = used.*;

    try findPath(T, allocator, snake_points, workspace, used, box.left, box.top, start[0], start[1], old, new);

    if (used.* == head_before) {
        appendPoint(snake_points, used, start);
    }

    const tail_before = used.*;

    try findPath(T, allocator, snake_points, workspace, used, end[0], end[1], box.right, box.bottom, old, new);

    if (used.* == tail_before) {
        appendPoint(snake_points, used, end);
    }
}

fn findMidpoint(comptime T: type, workspace: []isize, box: Box, old: []const T, new: []const T) !?Snake {
    if (box.size() == 0) {
        return null;
    }

    const size = box.size();
    const dmax: usize = size / 2 + size % 2;
    const sizeText = old.len + new.len;
    const frontier_len = 2 * (sizeText / 2 + sizeText % 2) + 3;

    const vf = workspace[0..frontier_len];
    const vb = workspace[frontier_len .. frontier_len * 2];

    vf[try toVectorIndex(1, dmax + 1)] = @intCast(box.left);
    vb[try toVectorIndex(1, dmax + 1)] = @intCast(box.bottom);

    const dmax_signed: isize = @intCast(dmax);
    var d: isize = 0;
    while (d <= dmax_signed) : (d += 1) {
        const middleSnake: ?Snake = try stepForward(T, box, vf, vb, d, old, new) orelse
            try stepBackward(T, box, vf, vb, d, old, new);
        if (middleSnake != null) {
            return middleSnake;
        }
    }

    return null;
}

fn toVectorIndex(k: isize, offset: usize) !usize {
    const off: isize = @intCast(offset);
    const shifted = k + off;

    if (shifted < 0) {
        return error.VectorIndexUnderflow;
    }

    return @intCast(shifted);
}

fn stepForward(comptime T: type, box: Box, vf: []isize, vb: []isize, d: isize, old: []const T, new: []const T) !?Snake {
    const size = box.size();
    const dmax = size / 2 + size % 2;
    const offset = dmax + 1;

    var k: isize = d;
    while (k >= -d) : (k -= 2) {
        const c = k - box.delta();
        var x: isize = 0;
        var prevX: isize = 0;

        if (k == -d) {
            x = vf[try toVectorIndex(k + 1, offset)];
            prevX = x;
        } else if (k != d and vf[try toVectorIndex(k - 1, offset)] < vf[try toVectorIndex(k + 1, offset)]) {
            x = vf[try toVectorIndex(k + 1, offset)];
            prevX = x;
        } else {
            prevX = vf[try toVectorIndex(k - 1, offset)];
            x = prevX + 1;
        }

        const x_relative = x - @as(isize, @intCast(box.left));

        const y_signed: isize =
            x_relative - k +
            @as(isize, @intCast(box.top));

        var y = y_signed;
        var prevY: isize = 0;
        if (d == 0 or x != prevX) {
            prevY = y;
        } else {
            prevY = y - 1;
        }

        while (x >= box.left and y >= box.top and x < box.right and y < box.bottom and old[@intCast(x)] == new[@intCast(y)]) {
            x += 1;
            y += 1;
        }

        vf[try toVectorIndex(k, offset)] = x;

        if (@mod(box.delta(), 2) != 0 and
            c >= -(d - 1) and c <= d - 1 and
            y >= vb[try toVectorIndex(c, offset)] and
            prevX >= box.left and prevY >= box.top and
            x <= box.right and y <= box.bottom)
        {
            return .{
                .start = .{ @intCast(prevX), @intCast(prevY) },
                .end = .{ @intCast(x), @intCast(y) },
            };
        }
    }

    return null;
}

fn stepBackward(comptime T: type, box: Box, vf: []isize, vb: []isize, d: isize, old: []const T, new: []const T) !?Snake {
    const size = box.size();
    const dmax = size / 2 + size % 2;
    const offset = dmax + 1;
    var c = d;
    while (c >= -d) : (c -= 2) {
        const k = c + box.delta();

        var y: isize = 0;
        var prevY: isize = 0;
        if (c == -d) {
            // move leftward
            y = vb[try toVectorIndex(c + 1, offset)];
            prevY = y;
        } else if (c != d and vb[try toVectorIndex(c - 1, offset)] > vb[try toVectorIndex(c + 1, offset)]) {
            // move leftward
            y = vb[try toVectorIndex(c + 1, offset)];
            prevY = y;
        } else {
            // move upward
            prevY = vb[try toVectorIndex(c - 1, offset)];
            y = prevY - 1;
        }

        const y_relative = y - @as(isize, @intCast(box.top));

        const x_signed: isize = y_relative + k + @as(isize, @intCast(box.left));

        var x = x_signed;
        var prevX: isize = 0;
        if (d == 0 or y != prevY) {
            prevX = x;
        } else {
            prevX = x + 1;
        }

        while (x > box.left and y > box.top and x <= box.right and y <= box.bottom and old[@intCast(x - 1)] == new[@intCast(y - 1)]) {
            x -= 1;
            y -= 1;
        }

        vb[try toVectorIndex(c, offset)] = y;

        if (@mod(box.delta(), 2) == 0 and
            k >= -d and k <= d and
            x <= vf[try toVectorIndex(k, offset)] and
            x >= box.left and y >= box.top and
            prevX <= box.right and prevY <= box.bottom)
        {
            return .{
                .start = .{ @intCast(x), @intCast(y) },
                .end = .{ @intCast(prevX), @intCast(prevY) },
            };
        }
    }

    return null;
}

// Implementation of linear space myers algorithm returning the compare script
pub fn diff(
    comptime T: type,
    allocator: std.mem.Allocator,
    old: []const T,
    new: []const T,
    max_d: usize,
) !Script {
    var distance: usize = 0;
    var script: Script = .empty;
    errdefer script.deinit(allocator);

    // Upper bound sicuro sui punti del path.
    const snake_points = try allocator.alloc(
        Point,
        old.len + new.len + 1,
    );
    defer allocator.free(snake_points);

    var used: usize = 0;
    const size = old.len + new.len;
    const dmax = size / 2 + size % 2;
    const frontier_len = 2 * dmax + 3;

    const workspace = try allocator.alloc(isize, frontier_len * 2);
    defer allocator.free(workspace);
    try findPath(T, allocator, snake_points, workspace, &used, 0, 0, old.len, new.len, old, new);

    if (used == 0) {
        return .empty;
    }

    const points = snake_points[0..used];

    try script.ensureTotalCapacity(
        allocator,
        old.len + new.len,
    );

    var i: usize = 0;
    while (i + 1 < points.len) : (i += 1) {
        var x = points[i][0];
        var y = points[i][1];

        const next_x = points[i + 1][0];
        const next_y = points[i + 1][1];

        while (x < next_x or y < next_y) {
            if (x < next_x and y < next_y and old[x] == new[y]) {
                appendEdit(&script, .KEEP, x, y);
                x += 1;
                y += 1;
            } else if (next_x - x > next_y - y) {
                appendEdit(&script, .DELETE, x, y);
                distance += 1;
                x += 1;
            } else if (next_y - y > next_x - x) {
                appendEdit(&script, .INSERT, x, y);
                distance += 1;
                y += 1;
            } else {
                return error.InvalidPath;
            }
        }
    }

    if (distance > max_d) return error.TooDifferent;

    return script;
}
