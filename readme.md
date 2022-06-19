# ziglua

A Zig library that provides a lightweight wrapper around the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) to embed the Lua virtual machine into your Zig programs. Currently tracks the latest Lua version (5.4.4).

Like the Lua C API, the ziglua API "emphasizes flexibility and simplicity... common tasks may involve several API calls. This may be boring, but it gives us full control over all the details" (_Programming In Lua 4th Edition_). However, ziglua takes advantage of Zig's features to make it easier and safer to interact with the Lua API.

* [Docs](https://github.com/natecraddock/ziglua/blob/master/docs.md)
* [Examples](https://github.com/natecraddock/ziglua/blob/master/docs.md#examples)

## Why use ziglua?

In a nutshell, ziglua is a simple wrapper around the C API you would get by using `@cImport()` to bind Lua. ziglua aims to mirror the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) as closely as possible, while improving ergonomics using Zig's features. For example:

* Zig error unions to enforce failure state handling
* Null-terminated slices instead of C strings
* Type-checked enums for parameters and return values
* Compiler-enforced checking of optional pointers
* Functions return `bool` rather than `int` to indicate success

While there are some helper functions added to complement the C API, ziglua aims to remain low-level.
This allows full access to Lua with the added benefits of Zig's improvements over C.

If you want something higher-level, perhaps try [zoltan](https://github.com/ranciere/zoltan).

## Getting Started

Adding ziglua to your project is easy. First add this repo as a git submodule, or copy the source into your repo. Then add the following to your `build.zig` file (assuming cloned/copied into a `lib/` subdirectory):

```zig
const ziglua = @import("lib/ziglua/build.zig");

pub fn build(b: *Builder) void {
    ...
    exe.addPackagePath("ziglua", "lib/ziglua/src/ziglua.zig");
    ziglua.link(b, exe, .{});
}
```

This will compile the Lua C sources and statically link with your project. Then simply import the ziglua package into your code! Here is a simple example that pushes and inspects an integer on the Lua stack:

```zig
const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var lua = try Lua.init(allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    std.debug.print("{}\n", .{lua.toInteger(1)});
}
```

See [docs.md](https://github.com/natecraddock/ziglua/blob/master/docs.md) for documentation and detailed [examples](https://github.com/natecraddock/ziglua/blob/master/docs.md#examples) of using ziglua.

## Status

Nearly all functions, types, and constants in the C API have been wrapped in ziglua. Only a few exceptions have been made when the function doesn't make sense in Zig (like functions using `va_list`).

All functions have been type checked, but only the standard C API has been tested fully. ziglua should be relatively stable and safe to use now, but is still new and changing frequently.

## Acknowledgements

Thanks to the following sources:

* [zoltan](https://github.com/ranciere/zoltan) for insights into compiling Lua with Zig
* [zig-autolua](https://github.com/daurnimator/zig-autolua) for help on writing an alloc function
* [mach-glfw](https://github.com/hexops/mach-glfw) for inspiration on a clean `build.zig`

And finally [Lua](https://lua.org). Thank you to the Lua team for providing a great language!
