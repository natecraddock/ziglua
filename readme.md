# Ziglua
[![shield showing current tests status](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml/badge.svg)](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml)
[![Discord](https://img.shields.io/discord/1196908820140671077?style=flat&logo=discord)](https://discord.com/invite/XpZqDFvAtK)

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

Find the archive url of the Ziglua version you want to integrate with your project. For example, the url for the commit **41a110981cf016465f72208c3f1732fd4c92a694** is https://github.com/natecraddock/ziglua/archive/41a110981cf016465f72208c3f1732fd4c92a694.tar.gz.

Then run `zig fetch --save <url>`. This will add the dependency to your `build.zig.zon` file.

Then in your `build.zig` file you can use the dependency.

```zig
pub fn build(b: *std.Build) void {
    // ... snip ...

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });

    // ... snip ...

    // add the ziglua module and lua artifact
    exe.root_module.addImport("ziglua", ziglua.module("ziglua"));

}
```

This will compile the Lua C sources and link with your project.

There are currently two additional options that can be passed to `b.dependency()`:

* `.lang`: Set the Lua language to build and embed. Defaults to `.lua54`. Possible values are `.lua51`, `.lua52`, `.lua53`, `.lua54`, and `luau`.
* `.shared`: Defaults to `false` for embedding in a Zig program. Set to `true` to dynamically link the Lua source code (useful for creating shared modules).

For example, here is a `b.dependency()` call that and links against a shared Lua 5.2 library:

```zig
const ziglua = b.dependency("ziglua", .{
    .target = target,
    .optimize = optimize,
    .lang = .lua52,
    .shared = true,
});
``````

The `ziglua` module will now be available in your code. Here is a simple example that pushes and inspects an integer on the Lua stack:

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

Thank you to the [Lua](https://lua.org) team for creating such a great language!
