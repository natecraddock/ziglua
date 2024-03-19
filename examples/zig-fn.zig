//! Registering a Zig function to be called from Lua

const std = @import("std");
const ziglua = @import("ziglua");

// It can be convenient to store a short reference to the Lua struct when
// it is used multiple times throughout a file.
const Lua = ziglua.Lua;

// A Zig function called by Lua must accept a single *Lua parameter and must return an i32.
// This is the Zig equivalent of the lua_CFunction typedef int (*lua_CFunction) (lua_State *L) in the C API
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

    // Initialize The Lua vm and get a reference to the main thread
    //
    // Passing a Zig allocator to the Lua state requires a stable pointer
    var lua = try Lua.init(&allocator);
    defer lua.deinit();

    // Push the adder function to the Lua stack.
    // Here we use ziglua.wrap() to convert from a Zig function to the lua_CFunction required by Lua.
    // This could be done automatically by pushFunction(), but that would require the parameter to be comptime-known.
    // The call to ziglua.wrap() is slightly more verbose, but has the benefit of being more flexible.
    lua.pushFunction(ziglua.wrap(adder));

    // Push the arguments onto the stack
    lua.pushInteger(10);
    lua.pushInteger(32);

    // Call the function. It accepts 2 arguments and returns 1 value
    // We use catch unreachable because we can verify this function call will not fail
    lua.protectedCall(2, 1, 0) catch unreachable;

    // The result of the function call is on the stack.
    // Use toInteger to read the integer at index 1
    std.debug.print("the result: {}\n", .{lua.toInteger(1) catch unreachable});

    // We can also register the function to a global and run from a Lua "program"
    lua.pushFunction(ziglua.wrap(adder));
    lua.setGlobal("add");

    // We need to open the base library so the global print() is available
    lua.openBase();

    // Our "program" is an inline string
    lua.doString(
        \\local sum = add(10, 32)
        \\print(sum)
    ) catch unreachable;
}
