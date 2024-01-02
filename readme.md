# Ziglua
[![shield showing current tests status](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml/badge.svg)](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml)

A Zig package that provides a complete and lightweight wrapper around the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4). Ziglua currently supports the latest releases of Lua 5.1, 5.2, 5.3, 5.4, and [Luau](https://luau-lang.org) and targets Zig master. Tagged versions of Ziglua are made for stable Zig releases.

Ziglua can be used in two ways, either
* **embedded** to statically embed the Lua VM in a Zig program,
* or as a shared **module** to create Lua libraries that can be loaded at runtime in other Lua-based software.

In both cases, Ziglua will compile Lua from source and link against your Zig code making it easy to create software that integrates with Lua without requiring any system Lua libraries.

Like the Lua C API, the Ziglua API "emphasizes flexibility and simplicity... common tasks may involve several API calls. This may be boring, but it gives us full control over all the details" (_Programming In Lua 4th Edition_). However, Ziglua takes advantage of Zig's features to make it easier and safer to interact with the Lua API.

## Documentation
Docs are a work in progress and are automatically generated for each push to main. Most functions and public declarations are documented.
* [Ziglua for Lua 5.1 Docs](https://natecraddock.github.io/ziglua/lua51/)
* [Ziglua for Lua 5.2 Docs](https://natecraddock.github.io/ziglua/lua52/)
* [Ziglua for Lua 5.3 Docs](https://natecraddock.github.io/ziglua/lua53/)
* [Ziglua for Lua 5.4 Docs](https://natecraddock.github.io/ziglua/lua54/)
* [Ziglua for Luau Docs](https://natecraddock.github.io/ziglua/luau/)

See [docs.md](https://github.com/natecraddock/ziglua/blob/main/docs.md) for more general information on Ziglua and how it differs from the C API.

Example code is included in the [examples](https://github.com/natecraddock/ziglua/tree/main/examples) directory.
* Run an example with `zig build run-example-<name>`
* Install an example with `zig build install-example-<name>`

## Why use Ziglua?
In a nutshell, Ziglua is a simple wrapper around the C API you would get by using Zig's `@cImport()`. Ziglua aims to mirror the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) as closely as possible, while improving ergonomics using Zig's features. For example:

* Zig error unions to require failure state handling
* Null-terminated slices instead of C strings
* Type-checked enums for parameters and return values
* Compiler-enforced checking of optional pointers
* Better types in many cases (e.g. `bool` instead of `int`)

While there are some helper functions added to complement the C API, Ziglua aims to remain low-level. This allows full access to the Lua API through a layer of Zig's improvements over C.

## Integrating Ziglua in your project
First create a `build.zig.zon` file in your Zig project if you do not already have one. Add a ziglua dependency.

```
.{
    .name = "myproject",
    .version = "0.0.1",
    .dependencies = .{
        .ziglua = .{
            // Use a tagged release of Ziglua tracking a stable Zig release
            .url = "https://github.com/natecraddock/ziglua/archive/refs/tags/0.2.0.tar.gz",

            // Or a url with a hash for a specific Ziglua commit
            .url = "https://github.com/natecraddock/ziglua/archive/ab111adb06d2d4dc187ee9e1e352617ca8659155.tar.gz",
        },
    }
}
```

When you run `zig build` it will instruct you to add a `.hash` field to this file.

In your `build.zig` file create and use the dependency

```zig
pub fn build(b: *std.Build) void {
    // ... snip ...

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });

    // ... snip ...

    // add the ziglua module and lua artifact
    exe.addModule("ziglua", ziglua.module("ziglua"));
    exe.linkLibrary(ziglua.artifact("lua"));

}
```

This will compile the Lua C sources and link with your project. The `ziglua` module will now be available in your code. Here is a simple example that pushes and inspects an integer on the Lua stack:

```zig
const std = @import("std");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

pub fn main() anyerror!void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the Lua vm
    var lua = try Lua.init(allocator);
    defer lua.deinit();

    // Add an integer to the Lua stack and retrieve it
    lua.pushInteger(42);
    std.debug.print("{}\n", .{try lua.toInteger(1)});
}
```

## Contributing
Please make suggestions, report bugs, and create pull requests. Anyone is welcome to contribute!

I only use a subset of the Lua API through Ziglua, so if there are parts that aren't easy to use or understand, please fix it yourself or let me know!

## Acknowledgements
Thanks to the following sources:

* [zoltan](https://github.com/ranciere/zoltan) for insights into compiling Lua with Zig
* [zig-autolua](https://github.com/daurnimator/zig-autolua) for help on writing an alloc function
* [mach-glfw](https://github.com/hexops/mach-glfw) for inspiration on a clean `build.zig`

And finally [Lua](https://lua.org). Thank you to the Lua team for creating such a great language!
