const std = @import("std");
const Io = std.Io;

const applyScript = @import("zdiff").applyScript;
const diff = @import("zdiff").diff;
const roundTrip = @import("zdiff").roundTrip;

pub fn main(init: std.process.Init) !void {
    const left = "aaaaaXaaaaaYaaaaa";
    const right = "aaaaaYbbbbb";
    var script = try diff(init.gpa, left, right);
    defer script.deinit(init.gpa);
    std.debug.print("Diff res: {any}\n", .{script.items});

    const result = try applyScript(init.gpa, script.items, left, right);
    defer init.gpa.free(result);
    std.debug.print("Result scripted: {s}\n", .{result});
}
