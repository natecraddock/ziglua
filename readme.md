# ziglua

A Zig library that provides a lightweight wrapper around the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) to embed the Lua virtual machine into your Zig programs. Currently tracks the latest Lua version (5.4.4).

## Why use ziglua?

In a nutshell, ziglua is a simple wrapper around the C API you would get by using `@cImport()` to bind Lua. ziglua aims to mirror the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) as closely as possible, while improving ergonomics using Zig's features. For example:

* Type-checked enums for parameters and return values
* Compiler-enforced checking of optional pointers
* Zig error unions to enforce error checking of failure states
* Functions return `bool` rather than `int` to indicate success

While there are a few helper functions added to complement the C API, ziglua aims to remain low-level. If you want something higher-level, perhaps try [zoltan](https://github.com/ranciere/zoltan).

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

All functions, types, and constants in the public Lua API have been wrapped in Zig **(268/268 identifiers)**.

However, only a small portion of the bindings have been tested. Many bugs likely lurk in the bindings at the moment. But having all of the functions exposed makes testing much easier.

So the current status is using the bindings, both in tests in this repo and in other projects that depend on ziglua. This will expose any bugs and show where things could be improved.

## Acknowledgements

Thanks to the following sources:

* [zoltan](https://github.com/ranciere/zoltan) for insights into compiling Lua with Zig
* [zig-autolua](https://github.com/daurnimator/zig-autolua) for help on writing an alloc function
* [mach-glfw](https://github.com/hexops/mach-glfw) for inspiration on a clean `build.zig`

And finally [Lua](https://lua.org). Thank you to the Lua team for providing a great language!
