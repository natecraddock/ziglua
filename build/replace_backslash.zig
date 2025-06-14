const std = @import("std");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 3) fatal("wrong number of arguments", .{});

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ input_file_path, @errorName(err) });
    };
    defer input_file.close();

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();
    std.debug.print("{s}\n", .{output_file_path});

    var buf_reader = std.io.bufferedReader(input_file.reader());
    var in_stream = buf_reader.reader();
    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (std.mem.indexOf(u8, line, "\"#line \"")) |_| {
            // replace backslash to slash
            _ = output_file.write(
                \\    wline("#line "..g_lineno..' "'..g_fname:gsub("\\", "/")..'"')
            ) catch @panic("write");
        } else {
            _ = output_file.write(line) catch @panic("write");
            _ = output_file.write("\n") catch @panic("write");
        }
    }

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
