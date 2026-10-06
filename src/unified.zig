const std = @import("std");

const diff = @import("myers.zig");
const hunk = @import("hunk.zig");
const token = @import("token.zig");

const ANSI_RED = "\x1b[31m";
const ANSI_GREEN = "\x1b[32m";
const ANSI_RESET = "\x1b[0m";

pub fn writeRange(w: *std.Io.Writer, start: usize, len: usize) !void {
    const first = if (len == 0) start else start + 1;
    if (len == 1) {
        try w.print("{d}", .{first});
    } else {
        try w.print("{d},{d}", .{ first, len });
    }
}

pub fn writeHunkHeader(w: *std.Io.Writer, old_start: usize, old_len: usize, new_start: usize, new_len: usize) !void {
    try w.writeAll("@@ -");
    try writeRange(w, old_start, old_len);
    try w.writeAll(" +");
    try writeRange(w, new_start, new_len);
    try w.writeAll(" @@\n");
}

inline fn renderToken(raw_text: []const u8, tok: token.Token) []const u8 {
    return std.mem.trim(u8, raw_text[tok.start .. tok.start + tok.len], "\n");
}

inline fn writeMarkerIfLast(stdout: *std.Io.Writer, index: usize, len: usize, incomplete: bool) !void {
    if (incomplete and index + 1 == len) try stdout.writeAll("\\ No newline at end of file\n");
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
    return viewTokenOffset(io, old, new, script, hunks, raw_old, raw_new, 0, false, false);
}

fn realWriteError(writer: *const std.Io.File.Writer, err: anyerror) anyerror {
    if (err == error.WriteFailed) {
        if (writer.err) |real| return real;
    }
    return err;
}

pub fn viewTokenOffset(
    io: std.Io,
    old: []token.Token,
    new: []token.Token,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
    raw_old: []const u8,
    raw_new: []const u8,
    line_offset: usize,
    old_incomplete: bool,
    new_incomplete: bool,
) !void {
    var stdout_buffer: [1024 * 32]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout_is_tty = try std.Io.File.stdout().isTty(io);
    renderTokenHunks(&stdout_writer.interface, stdout_is_tty, old, new, script, hunks, raw_old, raw_new, line_offset, old_incomplete, new_incomplete) catch |err|
        return realWriteError(&stdout_writer, err);
}

fn renderTokenHunks(
    stdout: *std.Io.Writer,
    stdout_is_tty: bool,
    old: []token.Token,
    new: []token.Token,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
    raw_old: []const u8,
    raw_new: []const u8,
    line_offset: usize,
    old_incomplete: bool,
    new_incomplete: bool,
) !void {
    for (hunks) |hu| {
        try writeHunkHeader(stdout, hu.old_start + line_offset, hu.old_len, hu.new_start + line_offset, hu.new_len);

        const old_hunk_end = hu.old_start + hu.old_len;
        const new_hunk_end = hu.new_start + hu.new_len;

        for (script[hu.first_run .. hu.first_run + hu.run_count]) |edit| {
            switch (edit.op) {
                diff.Op.KEEP => {
                    const start = @max(edit.startOld, hu.old_start);
                    const end = @min(edit.startOld + edit.len, old_hunk_end);

                    if (start < end) {
                        for (old[start..end], start..) |item, i| {
                            try stdout.writeByte(' ');
                            try stdout.writeAll(renderToken(raw_old, item));
                            try stdout.writeByte('\n');
                            try writeMarkerIfLast(stdout, i, old.len, old_incomplete);
                        }
                    }
                },
                diff.Op.DELETE => {
                    const start = @max(edit.startOld, hu.old_start);
                    const end = @min(edit.startOld + edit.len, old_hunk_end);

                    if (start < end) {
                        for (old[start..end], start..) |item, i| {
                            try stdout.writeAll(ANSI_RED);
                            try stdout.writeByte('-');
                            try stdout.writeAll(renderToken(raw_old, item));
                            try stdout.writeAll(ANSI_RESET);
                            try stdout.writeByte('\n');
                            try writeMarkerIfLast(stdout, i, old.len, old_incomplete);
                        }
                    }
                },
                diff.Op.INSERT => {
                    const start = @max(edit.startNew, hu.new_start);
                    const end = @min(edit.startNew + edit.len, new_hunk_end);
                    if (start < end) {
                        for (new[start..end], start..) |item, i| {
                            try stdout.writeAll(ANSI_GREEN);
                            try stdout.writeByte('+');
                            try stdout.writeAll(renderToken(raw_new, item));
                            try stdout.writeAll(ANSI_RESET);
                            try stdout.writeByte('\n');
                            try writeMarkerIfLast(stdout, i, new.len, new_incomplete);
                        }
                    }
                },
            }
        }
        if (stdout_is_tty) try stdout.flush(); // Show each hunk immediately in a terminal.
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
            try stdout.writeAll(ANSI_RED);
            try stdout.print("{x:0>2} ", .{byte});
            try stdout.writeAll(ANSI_RESET);
        },

        .INSERT => {
            try stdout.writeAll(ANSI_GREEN);
            try stdout.print("{x:0>2} ", .{byte});
            try stdout.writeAll(ANSI_RESET);
        },
    }
}

fn printAsciiByte(stdout: *std.Io.Writer, byte: u8, op: diff.Op) !void {
    const c = printable(byte);

    switch (op) {
        .KEEP => {
            try stdout.writeByte(c);
        },

        .DELETE => {
            try stdout.writeAll(ANSI_RED);
            try stdout.writeByte(c);
            try stdout.writeAll(ANSI_RESET);
        },

        .INSERT => {
            try stdout.writeAll(ANSI_GREEN);
            try stdout.writeByte(c);
            try stdout.writeAll(ANSI_RESET);
        },
    }
}

fn printPrefix(stdout: *std.Io.Writer, op: diff.Op) !void {
    switch (op) {
        .KEEP => try stdout.writeAll(" "),
        .DELETE => {
            try stdout.writeAll(ANSI_RED);
            try stdout.writeAll("- ");
            try stdout.writeAll(ANSI_RESET);
        },
        .INSERT => {
            try stdout.writeAll(ANSI_GREEN);
            try stdout.writeAll("+ ");
            try stdout.writeAll(ANSI_RESET);
        },
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
            try stdout.writeAll(" ");
        }

        if (i < bytes.len) {
            try printHexByte(stdout, bytes[i], op);
        } else {
            try stdout.writeAll("    ");
        }
    }

    try stdout.writeAll(" |");

    for (bytes) |byte| {
        try printAsciiByte(stdout, byte, op);
    }

    for (bytes.len..BYTES_PER_ROW) |_| {
        try stdout.writeAll(" ");
    }

    try stdout.writeAll("|\n");
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
    const stdout_is_tty = try std.Io.File.stdout().isTty(io);
    renderHexHunks(&stdout_writer.interface, stdout_is_tty, old, new, script, hunks) catch |err|
        return realWriteError(&stdout_writer, err);
}

fn renderHexHunks(
    stdout: *std.Io.Writer,
    stdout_is_tty: bool,
    old: []const u8,
    new: []const u8,
    script: []const diff.Edit,
    hunks: []const hunk.Hunk,
) !void {
    for (hunks) |hu| {
        try stdout.writeByte('\n');
        try writeHunkHeader(stdout, hu.old_start, hu.old_len, hu.new_start, hu.new_len);

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
