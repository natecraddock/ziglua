//! Simple Lua interpreter
//! This is a modified program from Programming in Lua 4th Edition

const std = @import("std");
const ziglua = @import("ziglua");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize The Lua vm and get a reference to the main thread
    var lua = try ziglua.Lua.init(allocator);
    defer lua.deinit();

    // Open the standard libraries
    lua.openLibs();

    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();

    var buffer: [256]u8 = undefined;
    while (true) {
        _ = try stdout.write("> ");

        // Read a line of input
        const len = try stdin.read(&buffer);
        if (len == 0) break; // EOF
        if (len >= buffer.len - 1) {
            try stdout.print("error: line too long!\n", .{});
            continue;
        }

        // Ensure the buffer is null-terminated so the Lua API can read the length
        buffer[len] = 0;

        // Compile a line of Lua code
        lua.loadString(buffer[0..len :0]) catch {
            try stdout.print("{s}\n", .{lua.toString(-1) catch unreachable});
            lua.pop(1);
            continue;
        };

        // Execute a line of Lua code
        lua.protectedCall(0, 0, 0) catch {
            try stdout.print("{s}\n", .{lua.toString(-1) catch unreachable});
            lua.pop(1);
        };
    }
}
