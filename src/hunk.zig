const std = @import("std");

const Edit = @import("myers.zig").Edit;
const Op = @import("myers.zig").Op;

pub const Hunk = struct {
    old_start: usize,
    old_len: usize,
    new_start: usize,
    new_len: usize,
    first_run: usize,
    run_count: usize, // script.items index
};

pub fn getGroup(script: []const Edit, context: usize, first_run: usize) Hunk {
    const max_gap = context +| context;

    var old_end: usize = script[0].startOld;
    var new_end: usize = script[0].startNew;

    const old_start = script[0].startOld;
    const new_start = script[0].startNew;

    var last_run: usize = 0;

    for (script, 0..) |elem, index| {
        if (elem.op == .KEEP and elem.len > max_gap) {
            break;
        }

        switch (elem.op) {
            .KEEP => {
                old_end += elem.len;
                new_end += elem.len;
            },
            .DELETE => {
                old_end += elem.len;
            },
            .INSERT => {
                new_end += elem.len;
            },
        }

        last_run = index;
    }

    return .{
        .old_start = old_start,
        .old_len = old_end - old_start,
        .new_start = new_start,
        .new_len = new_end - new_start,
        .first_run = first_run,
        .run_count = last_run + 1,
    };
}

pub fn hunks(
    alloc: std.mem.Allocator,
    script: []const Edit,
    old_size: usize,
    new_size: usize,
    context: usize,
) ![]Hunk {
    var hunks_list: std.ArrayList(Hunk) = .empty;

    var first_run: usize = 0;

    while (first_run < script.len) {

        // Cerca la prossima modifica
        while (first_run < script.len and script[first_run].op == .KEEP)
            first_run += 1;

        if (first_run == script.len)
            break;

        var hunk = getGroup(script[first_run..], context, first_run);

        const group_first = hunk.first_run;
        const group_last = group_first + hunk.run_count - 1;
        const next_group_search = group_last + 1;

        const old_group_end = hunk.old_start + hunk.old_len;
        const new_group_end = hunk.new_start + hunk.new_len;

        const padded_old_start = hunk.old_start -| context;
        const padded_new_start = hunk.new_start -| context;

        const padded_old_end = @min(old_size, old_group_end +| context);
        const padded_new_end = @min(new_size, new_group_end +| context);

        hunk.old_start = padded_old_start;
        hunk.old_len = padded_old_end - padded_old_start;

        hunk.new_start = padded_new_start;
        hunk.new_len = padded_new_end - padded_new_start;

        var hunk_first = group_first;
        var hunk_last = group_last;

        if (context > 0) {
            if (group_first > 0 and
                script[hunk_first - 1].op == .KEEP)
            {
                hunk_first -= 1;
            }

            if (hunk_last + 1 < script.len and
                script[hunk_last + 1].op == .KEEP)
            {
                hunk_last += 1;
            }
        }

        hunk.first_run = hunk_first;
        hunk.run_count = hunk_last - hunk_first + 1;

        try hunks_list.append(alloc, hunk);

        first_run = next_group_search;
    }

    return try hunks_list.toOwnedSlice(alloc);
}
