const std = @import("std");
const Io = std.Io;

const diff = @import("zdiff").diff;

pub fn main(init: std.process.Init) !void {
    var script = try diff(init.gpa, "ciao", "ciai");
    defer script.deinit(init.gpa);
    std.debug.print("Diff res: {any}\n", .{script.items});
}
