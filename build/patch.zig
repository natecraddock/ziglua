//! A simple script to apply a patch to a file
//! Does minimal validation and is just enough for patching Lua 5.1

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 4) @panic("Wrong number of arguments");

    const file_path = args[1];
    const patch_file_path = args[2];
    const output_path = args[3];

    const patch_file = patch_file: {
        const patch_file = try std.fs.cwd().openFile(patch_file_path, .{ .mode = .read_only });
        defer patch_file.close();
        var buf: [4096]u8 = undefined;
        var reader = patch_file.reader(&buf);
        break :patch_file try reader.interface.allocRemaining(allocator, .unlimited);
    };
    const chunk_details = Chunk.init(allocator, patch_file, 0) orelse @panic("No chunk data found");

    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    var in_buf: [4096]u8 = undefined;
    var reader = file.reader(&in_buf);

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();
    var out_buf: [4096]u8 = undefined;
    var writer = output.writer(&out_buf);

    var state: State = .copy;

    var line_number: usize = 1;
    while (true) : (line_number += 1) {
        if (line_number == chunk_details.src) state = .chunk;

        switch (state) {
            .copy => {
                _ = reader.interface.streamDelimiter(&writer.interface, '\n') catch |err| switch (err) {
                    error.EndOfStream => {
                        try writer.end();
                        return;
                    },
                    else => return err,
                };
                reader.interface.toss(1);
                try writer.interface.writeByte('\n');
            },
            .chunk => {
                const chunk = chunk_details.lines[line_number - chunk_details.src];
                switch (chunk.action) {
                    .remove => {
                        const line = try reader.interface.takeDelimiterExclusive('\n');
                        if (!std.mem.eql(u8, chunk.buf, line)) @panic("Failed to apply patch");
                    },
                    .keep => {
                        const line = try reader.interface.takeDelimiterExclusive('\n');
                        if (!std.mem.eql(u8, chunk.buf, line)) @panic("Failed to apply patch");
                        try writer.interface.writeAll(line);
                        try writer.interface.writeByte('\n');
                    },
                    .add => {
                        try writer.interface.writeAll(chunk.buf);
                        try writer.interface.writeByte('\n');
                    },
                }

                if (line_number - chunk_details.src == chunk_details.lines.len - 1) state = .copy;
            },
        }
    }
}

const State = enum { copy, chunk };

const Chunk = struct {
    lines: []Line,
    src: usize,
    dst: usize,

    const Line = struct {
        const Action = enum { remove, keep, add };

        action: Action,
        buf: []const u8,
    };

    fn init(arena: std.mem.Allocator, contents: []const u8, pos: usize) ?Chunk {
        var it = std.mem.tokenizeScalar(u8, contents[pos..], '\n');
        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "@@")) {
                const end = std.mem.indexOfPosLinear(u8, line, 3, "@@").?;
                const details = line[4 .. end - 2];

                const space_index = std.mem.indexOfScalar(u8, details, ' ').?;
                const src = getLineNumber(details[0..space_index]);
                const dst = getLineNumber(details[space_index + 1 ..]);

                var lines: std.ArrayListUnmanaged(Line) = .empty;
                while (true) {
                    const diff_line = it.next() orelse break;
                    if (std.mem.startsWith(u8, diff_line, "@@")) break;

                    const action: Line.Action = switch (diff_line[0]) {
                        '-' => .remove,
                        ' ' => .keep,
                        '+' => .add,
                        else => @panic("Bad patch file"),
                    };

                    lines.append(arena, .{ .action = action, .buf = diff_line[1..] }) catch unreachable;
                }

                return .{
                    .lines = lines.toOwnedSlice(arena) catch unreachable,
                    .src = src,
                    .dst = dst,
                };
            }
        }
        return null;
    }

    fn getLineNumber(buf: []const u8) usize {
        const comma = std.mem.indexOfScalar(u8, buf, ',').?;
        return std.fmt.parseInt(usize, buf[0..comma], 10) catch unreachable;
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
