const std = @import("std");
const Io = std.Io;

const applyScript = @import("zdiff").applyScript;
const diff = @import("zdiff").diff;
const hunk = @import("zdiff").hunk;
const roundTrip = @import("zdiff").roundTrip;
const token = @import("zdiff").token;
const unified = @import("zdiff").unified;

pub fn main(init: std.process.Init) !void {
    const old =
        \\The quick brown fox jumps over the lazy dog.
        \\This section should remain completely unchanged.
        \\The user has permission level: guest.
        \\Nothing interesting happens in this part of the text.
        \\It is intentionally long enough to separate two changes.
        \\Another unchanged sentence is placed right here.
        \\The server is running on port 8080.
        \\End of configuration.
    ;
    const new =
        \\The quick brown fox jumps over the lazy dog.
        \\This section should remain completely unchanged.
        \\The user can now access private resources.
        \\Nothing interesting happens in this part of the text.
        \\It is intentionally long enough to separate two changes.
        \\Another unchanged sentence is placed right here.
        \\The server is running on port 9090.
        \\End of configuration.
    ;
    var script = try diff(init.gpa, old, new, 6500);
    defer script.deinit(init.gpa);
    std.debug.print("Diff res: {any}\n", .{script.items});

    const result = try applyScript(init.gpa, script.items, old, new);
    defer init.gpa.free(result);
    std.debug.print("Result scripted: {s}\n", .{result});

    const hunks = try hunk.hunks(init.gpa, script.items, old.len, new.len, 10);
    defer init.gpa.free(hunks);
    std.debug.print("Hunks: {any}\n", .{hunks});

    // var keys =
    var internMap: std.array_hash_map.String(usize) = .empty;
    defer internMap.deinit(init.gpa);
    const tokens = try token.tokenizeBy(init.gpa, old, '\n', &internMap);
    defer init.gpa.free(tokens);
    std.debug.print("OLD Tokens: {any}\n", .{tokens});

    const tokensNew = try token.tokenizeBy(init.gpa, new, '\n', &internMap);
    defer init.gpa.free(tokensNew);
    std.debug.print("NEW Tokens: {any}\n", .{tokensNew});

    // unified.view(old, new, script.items, hunks);
}
