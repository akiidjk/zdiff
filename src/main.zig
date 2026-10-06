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
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
}

const exit_trouble: u8 = 2;

fn describe(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied, error.PermissionDenied => "Permission denied",
        error.IsDir => "Is a directory",
        error.OutOfMemory => "Out of memory",
        error.NoSpaceLeft => "No space left on device",
        error.TooDifferent => "Files too different",
        else => @errorName(err),
    };
}

fn fail(context: ?[]const u8, err: anyerror) noreturn {
    if (err == error.BrokenPipe) std.process.exit(exit_trouble);
    if (context) |c|
        std.debug.print("zdiff: {s}: {s}\n", .{ c, describe(err) })
    else
        std.debug.print("zdiff: {s}\n", .{describe(err)});
    std.process.exit(exit_trouble);
}

fn run() !void {
    const alloc = std.heap.c_allocator;

    const read_start = if (builtin.mode == .Debug) std.Io.Clock.now(.awake, io);
    const old = readFile(alloc, config.old) catch |err| fail(config.old, err);
    const new = readFile(alloc, config.new) catch |err| fail(config.new, err);

    if (builtin.mode == .Debug) {
        const read_end = std.Io.Clock.now(.awake, io);
        std.debug.print("[timing] read={d} ns\n", .{read_start.durationTo(read_end).toNanoseconds()});
    }

    const status = diff(io, alloc, old, new, config.binary) catch |err| fail(null, err);
    std.process.exit(status);
}

fn parseArgs(r: *cli.AppRunner) cli.AppRunner.Error!cli.ExecFn {
    // `getAction` owns this data, so these slices can live on the stack.
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
