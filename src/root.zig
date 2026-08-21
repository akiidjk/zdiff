const std = @import("std");
const Io = std.Io;

pub const hunk = @import("hunk.zig");
const myers = @import("myers.zig");
pub const token = @import("token.zig");
pub const unified = @import("unified.zig");

pub fn applyScript(comptime T: type, alloc: std.mem.Allocator, script: []const myers.Edit, old: []const T, new: []const T) ![]T {
    var out: std.ArrayList(T) = .empty;
    errdefer out.deinit(alloc);
    var i: usize = 0; // cursore su old
    var j: usize = 0; // cursore su new
    for (script) |edit| {
        if (edit.startOld != i or edit.startNew != j) return error.CursorMismatch;

        switch (edit.op) {
            .INSERT => {
                if (j >= new.len) return error.CursorOverrun;
                try out.appendSlice(alloc, new[j .. j + edit.len]);
                j += edit.len;
            },
            .DELETE => {
                if (i >= old.len) return error.CursorOverrun;
                i += edit.len;
            },
            .KEEP => {
                if (i >= old.len or j >= new.len) return error.CursorOverrun;
                try out.appendSlice(alloc, new[j .. j + edit.len]);
                i += edit.len;
                j += edit.len;
            },
        }
    }

    if (i != old.len or j != new.len) return error.IncompleteScript;
    return out.toOwnedSlice(alloc);
}

pub fn diff(io: std.Io, alloc: std.mem.Allocator, old: []const u8, new: []const u8, raw: bool) !void {
    if (raw) {
        var scriptWBytes = try myers.myers(u8, alloc, old, new, 6500);
        defer scriptWBytes.deinit(alloc);
        const hunksWBytes = try hunk.hunks(alloc, scriptWBytes.items, old.len, new.len, 1);
        defer alloc.free(hunksWBytes);
        try unified.viewHex(io, old, new, scriptWBytes.items, hunksWBytes);
    } else {
        var internMap: std.array_hash_map.String(usize) = .empty;
        defer internMap.deinit(alloc);
        const oldTokens = try token.tokenizeBy(alloc, old, '\n', &internMap);
        defer alloc.free(oldTokens.tokens);
        defer alloc.free(oldTokens.ids);

        const newTokens = try token.tokenizeBy(alloc, new, '\n', &internMap);
        defer alloc.free(newTokens.tokens);
        defer alloc.free(newTokens.ids);

        var scriptWTokens = try myers.myers(usize, alloc, oldTokens.ids, newTokens.ids, 6500);
        defer scriptWTokens.deinit(alloc);

        const hunksWTokens = try hunk.hunks(alloc, scriptWTokens.items, oldTokens.tokens.len, newTokens.tokens.len, 1);
        defer alloc.free(hunksWTokens);

        try unified.viewToken(io, oldTokens.tokens, newTokens.tokens, scriptWTokens.items, hunksWTokens, old, new);
    }
}
