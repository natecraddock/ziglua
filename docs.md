# Ziglua Documentation

*To avoid a duplication of efforts, Ziglua does not contain full documentation on the Lua C API. Please refer to the Lua C API Documentation for full details.*

This documentation provides

* An overview of Ziglua's structure and changes from the C API
* Safety considerations
* `build.zig` documentation
* Example code

Documentation on each individual function is found in the source code.

## Moving from the C API to Zig

While efforts have been made to keep the Ziglua API similar to the C API, many changes have been made including:

* Renaming or omitting functions
* Modifying parameters (names and types) and return values
* Additional helper functions have been added

With this in mind, here are some general guidelines to help when moving from the C to Zig APIs

### Naming

In general, most functions are named similarly to the original C functions. The `lua_` and `luaL_` prefixes have been removed, because all functions are in the `Lua` struct namespace. Additionally, all functions are in `camelCase` to match Zig naming style.

In the few cases when the [auxiliary library](https://www.lua.org/manual/5.4/manual.html#5) functions have the same name as a normal C API function, the suffix `Aux` is added to the function name to distinguish from the normal function.

For example, the functions `lua_newstate` and `luaL_newstate` are translated to `Lua.newState` and `Lua.newStateAux` respectively.

Because Zig best practice is to communicate intent precisely, some abbreviations are expanded to make names more clear, like renaming `pcall` to `protectedCall`.

### Lua Initialization

In the C API, there are two functions provided to initialize the main Lua state: `lua_newstate` and `luaL_newstate`. The former requires passing an allocator function to be used by Lua for all memory allocations, while the latter uses the default libc allocator.

Ziglua provides a third option with the `Lua.init(Allocator)` function, which accepts a Zig allocator. All three functions are available depending on your needs, but most likely you will want to use the `Lua.init(Allocator)` function. If you have special requirements for allocation, then `Lua.newState` would be useful. `Lua.newStateAux` is available if you wish to use the default libc allocator.

## Safety

The Ziglua API aims to be safer than the traditional C API. That said, the way that Lua operates means that Zig cannot protect you from all errors due to the use of `longjmp` in C.

Here is a list of the features Ziglua uses for greater safety:

### Errors

Many functions now return Zig errors rather than an integer code. The compiler will then ensure that the error is handled, or ignored. There are specific error types like `ziglua.Error.Runtime` for errors that have a specific meaning.

On the other hand, many functions either succeed or return an error. Rather than returning a boolean success code, these functions return the generic `ziglua.Error.Fail` to indicate failure. The type of failure can be determined in the context of the function called.

### Booleans

Functions that return or accept C boolean integers now use the Zig `bool` type.

### Slices

In cases where C functions use separate pointers and ints to keep track of strings, Ziglua uses a Zig slice to keep the data together.

The slices are typed to indicate the contents (zero-terminated, raw bytes, etc.)

### Enums

Ziglua uses enums instead of integer codes or strings to prevent passing an invalid value to a function.

### Optionals

Any value that can be `NULL` in the C API is marked as optional in Zig to enforce null checking.

## API Differences

The major differences between the C and Zig Lua APIs are described below. This includes identifier renaming and omissions.

### Continuations

All functions and types that deal with continuations have been renamed. For example, `KFunction` is now `LuaContFn`, and `lua_yieldk` is now `yieldCont`. One exception is the `KContext` type which has been simply renamed to `Context`. This is only ever used in continuation functions, so the `K` doesn't add much detail.

In general, just replace the "k" with the word "cont". This is just to make the API more clear and Zig-like.

### `lua_error` and `luaL_error`

Because `error` is a reserved word in Zig, these functions have been renamed to `raiseError` and `raiseErrorAux` respectively.

### `string` vs `lstring`

The "string" variant functions vs the "lstring" functions only differ by returning the length of the string. In Ziglua, the lstring functions are all named "bytes" instead. For example, `lua_tolstring` is `Lua.toBytes`. This is because these functions are typically used in cases when the string _might_ contain zeros before the null-terminating zero.

The "string" variant functions are safe to use when the string is known to be null terminated without inner zeros.

The length of the returned string is almost always needed, so `Lua.toString() returns a zero-terminated Zig slice of the bytes with the correct length.

### `lua_pushvfstring`

This function has been omitted because Zig does not have a va_list type, and `Lua.pushFString` works well enough for string formatting if variadic args are really needed.

### `lua_tointegerx` and `lua_tonumberx`

Both of these functions accept an `isnum` return parameter to indicate if the conversion to number was successful. In the Zig version, both functions return either the number, or an error indicating the conversion was unsuccessful, and the `isnum` parameter is omitted.

### `lua_pushliteral`

This is a macro for `lua_pushstring`, so use `Lua.pushString()` instead.

### `pcall`

Both `lua_pcall` and `lua_pcallk` are expanded to `protectedCall` and `protectedCallCont` for readability.

## Build Documentation

When integrating Ziglua into your projects, the following two statements are required:

1. `@import()` the `build.zig` file
2. `addPackage()` the Ziglua api

Note that this _must_ be done after setting the target and build mode, otherwise Ziglua will not know that information.

```zig
const ziglua = @import("lib/ziglua/build.zig");

pub fn build(b: *Builder) void {
    ...
    exe.addPackage(ziglua.linkAndPackage(b, exe, .{}));
}
```

This makes the `ziglua` package available in your project. Access with `@import("ziglua")`.

There are currently three options that can be passed in the third argument to `ziglua.linkAndPackage()`:

* `.use_apicheck`: defaults to **false**. When **true** defines the macro `LUA_USE_APICHECK` in debug builds. See [The C API docs](https://www.lua.org/manual/5.4/manual.html#4) for more information on this macro.

* `.version`: Set the Lua version to build and embed. Defaults to `.lua_54`. Possible values are `.lua_51`, `.lua_52`, `.lua_53`, and `.lua_54`.

* `.shared`: Defaults to `false` for embedding in a Zig program. Set to `true` to dynamically link the Lua source code (useful for creating shared modules).

For example, here is a `ziglua.linkAndPackage()` call that enables api check and embeds Lua 5.2:

```
exe.addPackage(ziglua.linkAndPackage(b, exe, .{ .use_apicheck = true, .version = .lua_52 }));
```

## Examples

Here are more thorough examples that show off the Ziglua bindings in context. All examples use the previously documented [`build.zig`](#build-documentation) setup.

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
```

This shows a basic interpreter that reads a string from stdin. That string is parsed and compiled as Lua code and then executed.

Notice that the functions `lua.loadString()` and `lua.protectedCall()` return errors that must be handled, here printing the error message that was placed on the stack.

The `lua.toString()` calls are both followed with `catch unreachable` in this example. This function can fail if the value at the given index is not a string. The stack should contain a Lua error string, so in this example we assert that it will not fail. We also could have passed a generic error string with `catch "Error"`

### Calling a Zig function

Registering a Zig function to be called from Lua is simple

```zig
const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

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
}
```

Notice the use of `ziglua.wrap`. This is because the function `fn adder(*Lua) i32` is a `ziglua.ZigFn`, when the `lua.pushFunction` call expects a `ziglua.CFn` type.

The `ziglua.wrap` function generates a new function at compile time that wraps the Zig function in a function compatible with the Lua C API. This could be done automatically by `lua.pushFunction`, but that would require the parameter to be comptime-known. The call to `ziglua.wrap` is slightly more verbose, but has the benefit of being more flexible.
