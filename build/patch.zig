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

    const patch_file = try std.fs.openFileAbsolute(patch_file_path, .{ .mode = .read_only });
    defer patch_file.close();
    const chunk_details = Chunk.next(allocator, patch_file) orelse @panic("No chunk data found");

    const file = try std.fs.openFileAbsolute(file_path, .{ .mode = .read_only });
    defer file.close();

    const output = try std.fs.createFileAbsolute(output_path, .{});
    defer output.close();

    var state: State = .copy;

    var line_number: usize = 1;
    while (true) : (line_number += 1) {
        if (line_number == chunk_details.src) state = .chunk;

        switch (state) {
            .copy => {
                const line = getLine(allocator, file) orelse return;
                _ = try output.write(line);
                _ = try output.write("\n");
            },
            .chunk => {
                const chunk = chunk_details.lines[line_number - chunk_details.src];
                switch (chunk.action) {
                    .remove => {
                        const line = getLine(allocator, file) orelse return;
                        if (!std.mem.eql(u8, chunk.buf, line)) @panic("Failed to apply patch");
                    },
                    .keep => {
                        const line = getLine(allocator, file) orelse return;
                        if (!std.mem.eql(u8, chunk.buf, line)) @panic("Failed to apply patch");
                        _ = try output.write(line);
                        _ = try output.write("\n");
                    },
                    .add => {
                        _ = try output.write(chunk.buf);
                        _ = try output.write("\n");
                    },
                }

                if (line_number - chunk_details.src == chunk_details.lines.len - 1) state = .copy;
            },
        }
    }
}

fn getLine(allocator: Allocator, file: File) ?[]u8 {
    return file.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
        error.EndOfStream => return null,
        else => @panic("Error"),
    };
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

    fn next(allocator: Allocator, file: File) ?Chunk {
        while (true) {
            const line = getLine(allocator, file) orelse return null;
            if (std.mem.startsWith(u8, line, "@@")) {
                const end = std.mem.indexOfPosLinear(u8, line, 3, "@@").?;
                const details = line[4 .. end - 2];

                const space_index = std.mem.indexOfScalar(u8, details, ' ').?;
                const src = getLineNumber(details[0..space_index]);
                const dst = getLineNumber(details[space_index + 1 ..]);

                var lines: std.ArrayListUnmanaged(Line) = .empty;
                while (true) {
                    const diff_line = getLine(allocator, file) orelse break;
                    if (std.mem.startsWith(u8, diff_line, "@@")) break;

                    const action: Line.Action = switch (diff_line[0]) {
                        '-' => .remove,
                        ' ' => .keep,
                        '+' => .add,
                        else => @panic("Bad patch file"),
                    };

                    lines.append(allocator, .{ .action = action, .buf = diff_line[1..] }) catch unreachable;
                }

                return .{
                    .lines = lines.toOwnedSlice(allocator) catch unreachable,
                    .src = src,
                    .dst = dst,
                };
            }
        }
    }

    fn getLineNumber(buf: []const u8) usize {
        const comma = std.mem.indexOfScalar(u8, buf, ',').?;
        return std.fmt.parseInt(usize, buf[0..comma], 10) catch unreachable;
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
