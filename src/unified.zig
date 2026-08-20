const std = @import("std");

const diff = @import("root.zig");
const hunk = @import("hunk.zig");
const token = @import("token.zig");

const ANSI_RED = "\x1b[31m";
const ANSI_GREEN = "\x1b[32m";
const ANSI_RESET = "\x1b[0m";

inline fn renderToken(raw_text: []const u8, tok: token.Token) []const u8 {
    return std.mem.trim(u8, raw_text[tok.start .. tok.start + tok.len], "\n");
}

pub fn viewToken(
    old: []token.Token,
    new: []token.Token,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
    raw_old: []const u8,
    raw_new: []const u8,
) !void {
    for (hunks) |hu| {
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
                            std.debug.print(" {s}\n", .{renderToken(raw_old, item)});
                        }
                    }
                },
                diff.Op.DELETE => {
                    const start = @max(edit.startOld, hu.old_start);
                    const end = @min(edit.startOld + edit.len, old_hunk_end);

                    if (start < end) {
                        for (old[start..end]) |item| {
                            std.debug.print("{s}-{s}{s}\n", .{ ANSI_RED, renderToken(raw_old, item), ANSI_RESET });
                        }
                    }
                },
                diff.Op.INSERT => {
                    const start = @max(edit.startNew, hu.new_start);
                    const end = @min(edit.startNew + edit.len, new_hunk_end);
                    if (start < end) {
                        for (new[start..end]) |item| {
                            std.debug.print("{s}+{s}{s}\n", .{ ANSI_GREEN, renderToken(raw_new, item), ANSI_RESET });
                        }
                    }
                },
            }
        }
    }
}

const BYTES_PER_ROW: usize = 16;

inline fn printable(byte: u8) u8 {
    return if (std.ascii.isPrint(byte)) byte else '.';
}

fn printHexByte(byte: u8, op: diff.Op) void {
    switch (op) {
        .KEEP => {
            std.debug.print("{x:0>2} ", .{byte});
        },

        .DELETE => {
            std.debug.print(
                "{s}{x:0>2}{s} ",
                .{ ANSI_RED, byte, ANSI_RESET },
            );
        },

        .INSERT => {
            std.debug.print(
                "{s}{x:0>2}{s} ",
                .{ ANSI_GREEN, byte, ANSI_RESET },
            );
        },
    }
}

fn printAsciiByte(byte: u8, op: diff.Op) void {
    const c = printable(byte);

    switch (op) {
        .KEEP => {
            std.debug.print("{c}", .{c});
        },

        .DELETE => {
            std.debug.print(
                "{s}{c}{s}",
                .{ ANSI_RED, c, ANSI_RESET },
            );
        },

        .INSERT => {
            std.debug.print(
                "{s}{c}{s}",
                .{ ANSI_GREEN, c, ANSI_RESET },
            );
        },
    }
}

fn printPrefix(op: diff.Op) void {
    switch (op) {
        .KEEP => std.debug.print("  ", .{}),
        .DELETE => std.debug.print("{s}- {s}", .{
            ANSI_RED,
            ANSI_RESET,
        }),
        .INSERT => std.debug.print("{s}+ {s}", .{
            ANSI_GREEN,
            ANSI_RESET,
        }),
    }
}

fn printHexRow(
    bytes: []const u8,
    offset: usize,
    op: diff.Op,
) void {
    printPrefix(op);

    std.debug.print("{x:0>8}  ", .{offset});

    for (0..BYTES_PER_ROW) |i| {
        if (i == 8) {
            std.debug.print(" ", .{});
        }

        if (i < bytes.len) {
            printHexByte(bytes[i], op);
        } else {
            .std.debug.print("   ", .{});
        }
    }

    std.debug.print(" |", .{});

    for (bytes) |byte| {
        printAsciiByte(byte, op);
    }

    for (bytes.len..BYTES_PER_ROW) |_| {
        std.debug.print(" ", .{});
    }

    std.debug.print("|\n", .{});
}

fn dumpRange(
    bytes: []const u8,
    absolute_start: usize,
    op: diff.Op,
) void {
    var pos: usize = 0;

    while (pos < bytes.len) {
        const remaining = bytes.len - pos;
        const row_len = @min(BYTES_PER_ROW, remaining);

        const row = bytes[pos .. pos + row_len];

        printHexRow(
            row,
            absolute_start + pos,
            op,
        );

        pos += row_len;
    }
}

pub fn viewHex(
    old: []const u8,
    new: []const u8,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
) !void {
    for (hunks) |hu| {
        std.debug.print(
            "\n@@ -{d},{d} +{d},{d} @@\n",
            .{
                hu.old_start + 1,
                hu.old_len,
                hu.new_start + 1,
                hu.new_len,
            },
        );

        const old_hunk_end = hu.old_start + hu.old_len;
        const new_hunk_end = hu.new_start + hu.new_len;

        const first_run = hu.first_run;
        const last_run = hu.first_run + hu.run_count;

        for (script[first_run..last_run]) |edit| {
            switch (edit.op) {
                .KEEP => {
                    const start = @max(
                        edit.startOld,
                        hu.old_start,
                    );

                    const end = @min(
                        edit.startOld + edit.len,
                        old_hunk_end,
                    );

                    if (start < end) {
                        dumpRange(
                            old[start..end],
                            start,
                            .KEEP,
                        );
                    }
                },

                .DELETE => {
                    const start = @max(
                        edit.startOld,
                        hu.old_start,
                    );

                    const end = @min(
                        edit.startOld + edit.len,
                        old_hunk_end,
                    );

                    if (start < end) {
                        dumpRange(
                            old[start..end],
                            start,
                            .DELETE,
                        );
                    }
                },

                .INSERT => {
                    const start = @max(
                        edit.startNew,
                        hu.new_start,
                    );

                    const end = @min(
                        edit.startNew + edit.len,
                        new_hunk_end,
                    );

                    if (start < end) {
                        dumpRange(
                            new[start..end],
                            start,
                            .INSERT,
                        );
                    }
                },
            }
        }
    }
}
