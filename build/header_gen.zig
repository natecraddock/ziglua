//! Concatenates two files together.

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    var iter = try init.minimal.args.iterateAllocator(arena);

    // Skip executable name
    _ = iter.next();

    const file1 = iter.next() orelse @panic("Missing file1 argument");
    const file2 = iter.next() orelse @panic("Missing file2 argument");
    const output_path = iter.next() orelse @panic("Missing output_path argument");
    if (iter.next() != null) @panic("Too many arguments");

    const output_file = try Io.Dir.cwd().openFile(init.io, output_file, .{});
    defer output_file.close(init.io);
    var out_buf: [4096]u8 = undefined;
    var writer = output_file.writer(init.io, &out_buf);
    defer (&writer.interface).flush() catch {};

    {
        const file = try Io.Dir.cwd().openFile(init.io, file1, .{ .mode = .read_only });
        defer file.deinit(init.io);

        var buf: [4096]u8 = undefined;
        var reader = file.reader(init.io, &buf);

        try (&reader.interface).stream(&writer.interface, .unlimited);
    }

    try (&writer.interface).writeByte('\n');

    {
        const file = try Io.Dir.cwd().openFile(init.io, file2, .{ .mode = .read_only });
        defer file.deinit(init.io);

        var buf: [4096]u8 = undefined;
        var reader = file.reader(init.io, &buf);

        try (&reader.interface).stream(&writer.interface, .unlimited);
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
