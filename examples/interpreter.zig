//! Simple Lua interpreter
//! This is a modified program from Programming in Lua 4th Edition

const std = @import("std");

// The zlua module is made available in build.zig
const zlua = @import("zlua");

const ReadError = error{BufferTooSmall};

fn readlineStdin(out_buf: []u8) anyerror!usize {
    var in_buf: [4096]u8 = undefined;
    var stdin_file = std.fs.File.stdin().reader(&in_buf);
    const stdin = &stdin_file.interface;
    const s = try stdin.takeDelimiterExclusive('\n');
    if (s.len < out_buf.len) {
        @memcpy(out_buf[0..s.len], s);
        return s.len;
    }
    return error.BufferTooSmall;
}

fn flushedStdoutPrint(comptime fmt: []const u8, args: anytype) !void {
    var out_buf: [4096]u8 = undefined;
    var w = std.fs.File.stdout().writer(&out_buf);
    const stdout = &w.interface;
    try stdout.print(fmt, args);
    try stdout.flush();
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize The Lua vm and get a reference to the main thread
    //
    // Passing a Zig allocator to the Lua state requires a stable pointer
    var lua = try zlua.Lua.init(allocator);
    defer lua.deinit();

    // Open all Lua standard libraries
    lua.openLibs();

    while (true) {
        try flushedStdoutPrint("> ", .{});

        // Read a line of input
        var buffer: [256]u8 = undefined;
        const len = readlineStdin(buffer[0 .. buffer.len - 1]) catch |err| {
            switch (err) {
                error.BufferTooSmall => {
                    try flushedStdoutPrint("error: line too long!\n", .{});
                    continue;
                },
                error.EndOfStream => break,
                else => return err,
            }
        };

        // Ensure the buffer is null-terminated so the Lua API can read the length
        buffer[len] = 0;

        // Compile a line of Lua code
        lua.loadString(buffer[0..len :0]) catch {
            // If there was an error, Lua will place an error string on the top of the stack.
            // Here we print out the string to inform the user of the issue.
            try flushedStdoutPrint("{s}\n", .{lua.toString(-1) catch unreachable});

            // Remove the error from the stack and go back to the prompt
            lua.pop(1);
            continue;
        };

        // Execute a line of Lua code
        lua.protectedCall(.{}) catch {
            // Error handling here is the same as above.
            try flushedStdoutPrint("{s}\n", .{lua.toString(-1) catch unreachable});
            lua.pop(1);
        };
    }
}
