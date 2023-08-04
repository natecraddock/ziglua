//! Registering a Zig function to be called from Lua

const std = @import("std");
const ziglua = @import("ziglua");

// It can be convenient to store a short reference to the Lua struct when
// it is used multiple times throughout a file.
const Lua = ziglua.Lua;

// A Zig function called by Lua must accept a single *Lua parameter and must return an i32.
fn adder(lua: *Lua) i32 {
    const a = lua.toInteger(1) catch 0;
    const b = lua.toInteger(2) catch 0;
    lua.pushInteger(a + b);
    return 1;
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var lua = try Lua.init(allocator);
    defer lua.deinit();

    lua.pushFunction(ziglua.wrap(adder));
    lua.pushInteger(10);
    lua.pushInteger(32);

    // assert that this function call will not error
    lua.protectedCall(2, 1, 0) catch unreachable;

    std.debug.print("the result: {}\n", .{lua.toInteger(1) catch unreachable});

    // Now register the function to a global and run from a Lua "program"
    lua.pushFunction(ziglua.wrap(adder));
    lua.setGlobal("add");

    lua.open(.{ .base = true });

    try lua.doString(
        \\local sum = add(10, 32)
        \\print(sum)
    );
}
