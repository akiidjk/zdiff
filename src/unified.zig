const std = @import("std");

const diff = @import("myers.zig");
const hunk = @import("hunk.zig");
const token = @import("token.zig");

const ANSI_RED = "\x1b[31m";
const ANSI_GREEN = "\x1b[32m";
const ANSI_RESET = "\x1b[0m";

inline fn renderToken(raw_text: []const u8, tok: token.Token) []const u8 {
    return std.mem.trim(u8, raw_text[tok.start .. tok.start + tok.len], "\n");
}

pub fn viewToken(
    io: std.Io,
    old: []token.Token,
    new: []token.Token,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
    raw_old: []const u8,
    raw_new: []const u8,
) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const stdout_is_tty = try std.Io.File.stdout().isTty(io);

    for (hunks) |hu| {
        try stdout.print(
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
                            try stdout.print(" {s}\n", .{renderToken(raw_old, item)});
                        }
                    }
                },
                diff.Op.DELETE => {
                    const start = @max(edit.startOld, hu.old_start);
                    const end = @min(edit.startOld + edit.len, old_hunk_end);

                    if (start < end) {
                        for (old[start..end]) |item| {
                            try stdout.print("{s}-{s}{s}\n", .{ ANSI_RED, renderToken(raw_old, item), ANSI_RESET });
                        }
                    }
                },
                diff.Op.INSERT => {
                    const start = @max(edit.startNew, hu.new_start);
                    const end = @min(edit.startNew + edit.len, new_hunk_end);
                    if (start < end) {
                        for (new[start..end]) |item| {
                            try stdout.print("{s}+{s}{s}\n", .{ ANSI_GREEN, renderToken(raw_new, item), ANSI_RESET });
                        }
                    }
                },
            }
        }
        if (stdout_is_tty) try stdout.flush(); // flush each hunk
    }
    try stdout.flush();
}

const BYTES_PER_ROW: usize = 16;

inline fn printable(byte: u8) u8 {
    return if (std.ascii.isPrint(byte)) byte else '.';
}

fn printHexByte(stdout: *std.Io.Writer, byte: u8, op: diff.Op) !void {
    switch (op) {
        .KEEP => {
            try stdout.print("{x:0>2} ", .{byte});
        },

        .DELETE => {
            try stdout.print(
                "{s}{x:0>2}{s} ",
                .{ ANSI_RED, byte, ANSI_RESET },
            );
        },

        .INSERT => {
            try stdout.print(
                "{s}{x:0>2}{s} ",
                .{ ANSI_GREEN, byte, ANSI_RESET },
            );
        },
    }
}

fn printAsciiByte(stdout: *std.Io.Writer, byte: u8, op: diff.Op) !void {
    const c = printable(byte);

    switch (op) {
        .KEEP => {
            try stdout.print("{c}", .{c});
        },

        .DELETE => {
            try stdout.print(
                "{s}{c}{s}",
                .{ ANSI_RED, c, ANSI_RESET },
            );
        },

        .INSERT => {
            try stdout.print(
                "{s}{c}{s}",
                .{ ANSI_GREEN, c, ANSI_RESET },
            );
        },
    }
}

fn printPrefix(stdout: *std.Io.Writer, op: diff.Op) !void {
    switch (op) {
        .KEEP => try stdout.print("  ", .{}),
        .DELETE => try stdout.print("{s}- {s}", .{
            ANSI_RED,
            ANSI_RESET,
        }),
        .INSERT => try stdout.print("{s}+ {s}", .{
            ANSI_GREEN,
            ANSI_RESET,
        }),
    }
}

fn printHexRow(
    stdout: *std.Io.Writer,
    bytes: []const u8,
    offset: usize,
    op: diff.Op,
) !void {
    try printPrefix(stdout, op);

    try stdout.print("{x:0>8}  ", .{offset});

    for (0..BYTES_PER_ROW) |i| {
        if (i == 8) {
            try stdout.print(" ", .{});
        }

        if (i < bytes.len) {
            try printHexByte(stdout, bytes[i], op);
        } else {
            try stdout.print("   ", .{});
        }
    }

    try stdout.print(" |", .{});

    for (bytes) |byte| {
        try printAsciiByte(stdout, byte, op);
    }

    for (bytes.len..BYTES_PER_ROW) |_| {
        try stdout.print(" ", .{});
    }

    try stdout.print("|\n", .{});
}

fn dumpRange(
    stdout: *std.Io.Writer,
    bytes: []const u8,
    absolute_start: usize,
    op: diff.Op,
) !void {
    var pos: usize = 0;

    while (pos < bytes.len) {
        const remaining = bytes.len - pos;
        const row_len = @min(BYTES_PER_ROW, remaining);

        const row = bytes[pos .. pos + row_len];

        try printHexRow(
            stdout,
            row,
            absolute_start + pos,
            op,
        );

        pos += row_len;
    }
}

pub fn viewHex(
    io: std.Io,
    old: []const u8,
    new: []const u8,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const stdout_is_tty = try std.Io.File.stdout().isTty(io);

    for (hunks) |hu| {
        try stdout.print(
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
                        try dumpRange(
                            stdout,
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
                        try dumpRange(
                            stdout,
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
                        try dumpRange(
                            stdout,
                            new[start..end],
                            start,
                            .INSERT,
                        );
                    }
                },
            }
        }

        if (stdout_is_tty) try stdout.flush();
    }

    try stdout.flush();
}
