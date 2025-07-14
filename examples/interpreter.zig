//! Simple Lua interpreter
//! This is a modified program from Programming in Lua 4th Edition

const std = @import("std");

// The zlua module is made available in build.zig
const zlua = @import("zlua");

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

    var in_buf: [4096]u8 = undefined;
    var out_buf: [4096]u8 = undefined;
    var stdin_file = std.fs.File.stdin().reader(&in_buf);
    const stdin = &stdin_file.interface;
    var stdout_file = std.fs.File.stdout().writer(&out_buf);
    const stdout = &stdout_file.interface;

    var buffer: [256]u8 = undefined;
    while (true) {
        _ = try stdout.writeAll("> ");

        // Read a line of input
        const len = try stdin.readSliceShort(&buffer);
        if (len == 0) break; // EOF
        if (len >= buffer.len - 1) {
            try stdout.print("error: line too long!\n", .{});
            continue;
        }

        // Ensure the buffer is null-terminated so the Lua API can read the length
        buffer[len] = 0;

        // Compile a line of Lua code
        lua.loadString(buffer[0..len :0]) catch {
            // If there was an error, Lua will place an error string on the top of the stack.
            // Here we print out the string to inform the user of the issue.
            try stdout.print("{s}\n", .{lua.toString(-1) catch unreachable});

            // Remove the error from the stack and go back to the prompt
            lua.pop(1);
            continue;
        };

        // Execute a line of Lua code
        lua.protectedCall(.{}) catch {
            // Error handling here is the same as above.
            try stdout.print("{s}\n", .{lua.toString(-1) catch unreachable});
            lua.pop(1);
        };
    }
}
