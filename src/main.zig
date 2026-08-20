const std = @import("std");
const Io = std.Io;

const applyScript = @import("zdiff").applyScript;
const hunk = @import("zdiff").hunk;
const myers = @import("zdiff").myers;
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

    var internMap: std.array_hash_map.String(usize) = .empty;
    defer internMap.deinit(init.gpa);
    const oldTokens = try token.tokenizeBy(init.gpa, old, '\n', &internMap);
    defer init.gpa.free(oldTokens.tokens);
    defer init.gpa.free(oldTokens.ids);
    std.debug.print("OLD Tokens: {any}\n", .{oldTokens});

    const newTokens = try token.tokenizeBy(init.gpa, new, '\n', &internMap);
    defer init.gpa.free(newTokens.tokens);
    defer init.gpa.free(newTokens.ids);
    std.debug.print("NEW Tokens: {any}\n", .{newTokens});

    var scriptWTokens = try myers(usize, init.gpa, oldTokens.ids, newTokens.ids, 6500);
    defer scriptWTokens.deinit(init.gpa);
    std.debug.print("Diff res: {any}\n", .{scriptWTokens.items});

    const resultWToken = try applyScript(usize, init.gpa, scriptWTokens.items, oldTokens.ids, newTokens.ids);
    defer init.gpa.free(resultWToken);
    std.debug.print("Result scripted: {any}\n", .{resultWToken});

    const hunksWTokens = try hunk.hunks(init.gpa, scriptWTokens.items, oldTokens.tokens.len, newTokens.tokens.len, 1);
    defer init.gpa.free(hunksWTokens);
    std.debug.print("Hunks: {any}\n", .{hunksWTokens});

    try unified.viewToken(oldTokens.tokens, newTokens.tokens, scriptWTokens.items, hunksWTokens, old, new);

    std.debug.print("========================= BYTES ============================== \n", .{});

    var scriptWBytes = try myers(u8, init.gpa, old, new, 6500);
    defer scriptWBytes.deinit(init.gpa);
    std.debug.print("Diff res: {any}\n", .{scriptWBytes.items});

    const resultWBytes = try applyScript(u8, init.gpa, scriptWBytes.items, old, new);
    defer init.gpa.free(resultWBytes);
    std.debug.print("Result scripted: {s}\n", .{resultWBytes});

    const hunksWBytes = try hunk.hunks(init.gpa, scriptWBytes.items, old.len, new.len, 1);
    defer init.gpa.free(hunksWBytes);
    std.debug.print("Hunks: {any}\n", .{hunksWBytes});

    try unified.viewHex(old, new, scriptWBytes.items, hunksWBytes);
}
