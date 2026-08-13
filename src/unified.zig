const std = @import("std");

const diff = @import("root.zig");
const hunk = @import("hunk.zig");

const ANSI_RED = "\x1b[31m";
const ANSI_GREEN = "\x1b[32m";
const ANSI_RESET = "\x1b[0m";

pub fn view(old: []const u8, new: []const u8, edits: []diff.Edit, hunks: []hunk.Hunk) void {
    _ = new; // autofix
    for (hunks) |hu| { // Per ogni hunks
        std.debug.print("@@ @@", .{});
        var i: usize = 0;
        while (i < hu.run_count) : (i += 1) { // Itero da first run in poi per il numero run_count che e' il numero di edit
            for (edits[hu.first_run..]) |edit| {
                switch (edit.op) {
                    diff.Op.KEEP => {
                        std.debug.print("{s}\n", .{old[edit.startOld .. edit.startOld + edit.len]});
                    },
                    diff.Op.INSERT => {
                        std.debug.print("{s}+{s}{s}\n", .{ ANSI_GREEN, old[edit.startOld .. edit.startOld + edit.len], ANSI_RESET });
                    },
                    diff.Op.DELETE => {
                        std.debug.print("{s}-{s}{s}\n", .{ ANSI_RED, old[edit.startOld .. edit.startOld + edit.len], ANSI_RESET });
                    },
                }
            }
        }
    }
}
