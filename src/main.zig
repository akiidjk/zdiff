const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const cli = @import("cli");
const diff = @import("zdiff").diff;

var io: std.Io = undefined;

var config = struct {
    old: []const u8 = undefined,
    new: []const u8 = undefined,
    binary: bool = false,
}{};

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.Io.Dir.cwd().openFile(io, path, .{
        .mode = .read_only,
        .lock = .exclusive,
    })) |file| {
        defer file.close(io);

        const buf = try allocator.alloc(u8, try file.length(io));
        var reader = file.reader(io, buf);
        reader.interface.readSliceAll(buf) catch |err| switch (err) {
            error.ReadFailed => return reader.err.?,
            else => return err,
        };
        return buf;
    } else |err| {
        return err;
    }
}

fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const read_start = if (builtin.mode == .Debug) std.Io.Clock.now(.awake, io);
    const old = try readFile(alloc, config.old);
    const new = try readFile(alloc, config.new);

    if (builtin.mode == .Debug) {
        const read_end = std.Io.Clock.now(.awake, io);
        std.debug.print("[timing] read={d} ns\n", .{read_start.durationTo(read_end).toNanoseconds()});
    }

    try diff(io, alloc, old, new, config.binary);
}

fn parseArgs(r: *cli.AppRunner) cli.AppRunner.Error!cli.ExecFn {
    // Since we call r.getAction in this function, all r.alloc* invocation are unnecessary.
    // We can directly pass slices of commands, options, and positional arguments,
    // like `.options = &.{....}`
    const app = cli.App{
        .option_envvar_prefix = "ZDIFF_",
        .command = cli.Command{
            .name = "zdiff",
            .description = cli.Description{
                .one_line = "Zig replacemente for diff command",
            },
            .target = cli.CommandTarget{ .action = cli.CommandAction{
                .positional_args = .{
                    .required = &.{
                        cli.PositionalArg{ .name = "Old", .help = "The old file", .value_ref = r.mkRef(&config.old) },
                        cli.PositionalArg{ .name = "New", .help = "The new file", .value_ref = r.mkRef(&config.new) },
                    },
                },
                .exec = run,
            } },
            .options = try r.allocOptions(&.{
                .{
                    .long_name = "binary",
                    .help = "compute the byte-by-byte diff between the files",
                    .short_alias = 'x',
                    .value_ref = r.mkRef(&config.binary),
                    .required = false,
                    .value_name = "BINARY",
                },
            }),
        },
        .version = "0.1.0",
        .author = "akiidjk & contributors",
    };

    return r.getAction(&app);
}

pub fn main(init: std.process.Init) !void {
    io = init.io;
    var r = cli.AppRunner.init(&init);
    defer r.deinit();

    const action = try parseArgs(&r);
    return action();
}
