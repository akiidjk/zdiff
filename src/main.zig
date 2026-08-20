const std = @import("std");
const Io = std.Io;

const applyScript = @import("zdiff").applyScript;
const diff = @import("zdiff").diff;
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

    try diff(init.gpa, old, new, false);

    try diff(init.gpa, old, new, true);
}
