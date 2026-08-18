const std = @import("std");

const diff = @import("root.zig");
const hunk = @import("hunk.zig");
const token = @import("token.zig");

const ANSI_RED = "\x1b[31m";
const ANSI_GREEN = "\x1b[32m";
const ANSI_RESET = "\x1b[0m";

pub fn renderToken(raw_text: []const u8, tok: token.Token) []const u8 {
    return std.mem.trim(u8, raw_text[tok.start .. tok.start + tok.len], "\n");
}

pub fn view(
    comptime T: type,
    alloc: std.mem.Allocator,
    old: []const T,
    new: []const T,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
    raw_old: []const u8,
    raw_new: []const u8,
    renderItem: fn ([]const u8, T) []const u8,
) !void {
    _ = alloc; // autofix
    for (hunks) |hu| { // Per ogni hunks
        std.debug.print(
            "@@ -{d},{d} +{d},{d} @@\n",
            .{
                hu.old_start + 1,
                hu.old_len,
                hu.new_start + 1,
                hu.new_len,
            },
        );

        const old_hunk_end = hu.old_start + hu.old_len;
        const new_hunk_end = hu.new_start + hu.new_len;

        for (script[hu.first_run .. hu.first_run + hu.run_count]) |edit| {
            switch (edit.op) {
                diff.Op.KEEP => {
                    const start = @max(edit.startOld, hu.old_start);
                    const end = @min(edit.startOld + edit.len, old_hunk_end);

                    if (start < end) {
                        for (old[start..end]) |item| {
                            std.debug.print(" {s}\n", .{renderItem(raw_old, item)});
                        }
                    }
                },
                diff.Op.DELETE => {
                    const start = @max(edit.startOld, hu.old_start);
                    const end = @min(edit.startOld + edit.len, old_hunk_end);

                    if (start < end) {
                        for (old[start..end]) |item| {
                            std.debug.print("{s}-{s}{s}\n", .{ ANSI_RED, renderItem(raw_old, item), ANSI_RESET });
                        }
                    }
                },
                diff.Op.INSERT => {
                    const start = @max(edit.startNew, hu.new_start);
                    const end = @min(edit.startNew + edit.len, new_hunk_end);
                    if (start < end) {
                        for (new[start..end]) |item| {
                            std.debug.print("{s}+{s}{s}\n", .{ ANSI_GREEN, renderItem(raw_new, item), ANSI_RESET });
                        }
                    }
                },
            }
        }
    }
}
