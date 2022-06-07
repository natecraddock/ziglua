# ziglua Documentation

*To avoid a duplication of efforts, ziglua does not contain full documentation on the Lua C API. Please refer to [the Lua C API Documentation](https://www.lua.org/manual/5.4/manual.html#4) for full details.*

This documentation provides

* An overview of ziglua's structure
* `build.zig` documentation
* Safety considerations
* API Differences
* Example code

## Moving from the C API to Zig

While efforts have been made to keep the ziglua API similar to the C API, many changes have been made including:

* Renaming or omitting functions
* Modifying parameters (names and types) and return values
* Additional helper functions have been added

With this in mind, here are some general guidelines to help guide when moving from the C to Zig APIs

### Naming

In general, most functions are named similarly to the original C functions. The `lua_` and `luaL_` prefixes have been removed, because all functions are in the `Lua` struct namespace. Additionally, all functions are in `camelCase` to match Zig naming style.

In the few cases when the [auxiliary library](https://www.lua.org/manual/5.4/manual.html#5) functions have the same name as a normal C API function, the suffix `Aux` is added to the function name to distinguish from the normal function.

For example, the functions `lua_newstate` and `luaL_newstate` are translated to `Lua.newState` and `Lua.newStateAux` respectively.

### Lua Initialization

In the C API, there are two functions provided to initialize the main Lua state: `lua_newstate` and `luaL_newstate`. The former requires passing an allocator function to be used by Lua for all memory allocations, while the latter uses the default libc allocator.

Ziglua provides a third option with the `Lua.init(Allocator)` function, which accepts a traditional Zig allocator. All three functions are available depending on your needs, but most likely you will want to use the `init` function. If you have special requirements for allocation, then `Lua.newState` would be useful. `Lua.newStateAux` is available, but Zig cannot track allocations made by libc so this is less safe.

## API Differences

The major differences between the C and Zig Lua APIs are described below. This includes identifier renaming and omissions.

### `lua_tostring` and `lua_tolstring`

These functions have been combined into `Lua.toString()`. The function `lua_tostring` is a macro around `lua_tolstring` and does not return the length of the string.

The length of the returned string is almost always needed, so `Lua.toString() returns a zero-terminated Zig slice of the bytes with the correct length.

### `lua_tointegerx` and `lua_tonumberx`

Both of these functions accept an `isnum` return parameter to indicate if the conversion to number was successful. In the Zig version, both functions return either the number, or an error indicating the conversion was unsuccessful, and the `isnum` parameter is omitted.

### `lua_pushliteral`

This is just a macro for `lua_pushstring`, so just use `Lua.pushString()` instead.

## Build Documentation

When integrating ziglua into your projects, the following three statements are required:

1. `@import()` the `build.zig` file
2. `addPackagePath` the ziglua api
3. `ziglua.link()` the library with your executable

Note that this _must_ be done after setting the target and build mode, otherwise ziglua will not know that information.

```zig
const ziglua = @import("lib/ziglua/build.zig");

pub fn build(b: *Builder) void {
    ...
    exe.addPackagePath("ziglua", "lib/ziglua/src/ziglua.zig");
    ziglua.link(b, exe, .{});
}
```

There is currently one option that can be passed in the third argument to `ziglua.link()`:

* `.use_apicheck`: defaults to **false**. When **true** defines the macro `LUA_USE_APICHECK` in debug builds. See [The C API docs](https://www.lua.org/manual/5.4/manual.html#4) for more information on this macro.

## Examples

Here are more thorough examples that show off the ziglua bindings in context. All examples use previously documented [`build.zig`](#build-documentation) setup.

### Simple Lua Interpreter

This is a modified program from _Programming In Lua 4th Edition_

```zig
const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize The Lua vm and get a reference to the main thread
    var lua = try Lua.init(allocator);
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
            try stdout.print("{s}\n", .{lua.toString(-1)});
            lua.pop(1);
            continue;
        };

        // Execute a line of Lua code
        lua.protectedCall(0, 0, 0) catch {
            try stdout.print("{s}\n", .{lua.toString(-1)});
            lua.pop(1);
        };
    }
}
```

This shows a basic interpreter that reads a string from stdin. That string is parsed and compiled as Lua code and then executed.

Notice that the functions `lua.loadString()` and `lua.protectedCall()` return errors that must be handled, here printing the error message that was placed on the stack.
