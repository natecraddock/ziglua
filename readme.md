# Ziglua

[![shield showing current tests status](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml/badge.svg)](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml)

A Zig library that provides a complete and lightweight wrapper around the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4). Ziglua currently supports the latest releases of Lua 5.1, 5.2, 5.3, and 5.4 and targets Zig 0.10.0.

Ziglua can be used in two ways, either
* **embedded** to statically embed the Lua VM in a Zig program,
* or as a shared **module** to create Lua libraries that can be loaded at runtime in other Lua-based software.

In both cases, Ziglua will compile Lua from source and link against your Zig code making it easy to create software that integrates with Lua without requiring any system Lua libraries.

Like the Lua C API, the Ziglua API "emphasizes flexibility and simplicity... common tasks may involve several API calls. This may be boring, but it gives us full control over all the details" (_Programming In Lua 4th Edition_). However, Ziglua takes advantage of Zig's features to make it easier and safer to interact with the Lua API.

* [Docs](https://github.com/natecraddock/ziglua/blob/master/docs.md)
* [Examples](https://github.com/natecraddock/ziglua/blob/master/docs.md#examples)
* [Changelog](https://github.com/natecraddock/ziglua/blob/master/changelog.md)

## Why use Ziglua?

In a nutshell, Ziglua is a simple wrapper around the C API you would get by using Zig's `@cImport()`. Ziglua aims to mirror the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) as closely as possible, while improving ergonomics using Zig's features. For example:

* Zig error unions to require failure state handling
* Null-terminated slices instead of C strings
* Type-checked enums for parameters and return values
* Compiler-enforced checking of optional pointers
* Better types in many cases (e.g. `bool` instead of `int`)

While there are some helper functions added to complement the C API, Ziglua aims to remain low-level. This allows full access to the Lua API through a layer of Zig's improvements over C.

If you want something higher-level (but doesn't expose the full API), perhaps try [zoltan](https://github.com/ranciere/zoltan).

## Getting Started

Adding Ziglua to your project takes only a couple of steps. First add this repo as a git submodule, or copy the source into your project (one day the Zig package manager will make this easier). Then add the following to your `build.zig` file (assuming cloned/copied into a `lib/` subdirectory):

```zig
// use the path to the Ziglua build.zig file
const ziglua = @import("lib/ziglua/build.zig");

pub fn build(b: *Builder) void {
    ...
    exe.addPackage(ziglua.linkAndPackage(b, exe, .{}));
}
```

This will compile the Lua C sources and statically link with your project. Then simply import the `ziglua` package into your code. Here is a simple example that pushes and inspects an integer on the Lua stack:

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
    std.debug.print("{}\n", .{try lua.toInteger(1)});
}
```

See [docs.md](https://github.com/natecraddock/ziglua/blob/master/docs.md) for documentation and detailed [examples](https://github.com/natecraddock/ziglua/blob/master/docs.md#examples) of using Ziglua.

## Status

Nearly all functions, types, and constants in the C API have been wrapped in Ziglua. Only a few exceptions have been made when the function doesn't make sense in Zig (like functions using `va_list`).

Nearly all functions have associated Zig tests. Ziglua should be relatively stable and safe to use now, but I am still polishing things and function signatures may change from time to time.

## Contributing

Please make suggestions, report bugs, and create pull requests. Anyone is welcome to contribute!

## Acknowledgements

Thanks to the following sources:

* [zoltan](https://github.com/ranciere/zoltan) for insights into compiling Lua with Zig
* [zig-autolua](https://github.com/daurnimator/zig-autolua) for help on writing an alloc function
* [mach-glfw](https://github.com/hexops/mach-glfw) for inspiration on a clean `build.zig`

And finally [Lua](https://lua.org). Thank you to the Lua team for creating and sharing such a great language!
