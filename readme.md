# Ziglua
[![shield showing current tests status](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml/badge.svg)](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml)
[![Discord](https://img.shields.io/discord/1196908820140671077?style=flat&logo=discord)](https://discord.com/invite/XpZqDFvAtK)

Zig bindings for the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4). Ziglua currently supports the latest releases of Lua 5.1, 5.2, 5.3, 5.4, and [Luau](https://luau-lang.org).

Ziglua can be used in two ways, either
* **embedded** to statically embed the Lua VM in a Zig program,
* or as a shared **module** to create Lua libraries that can be loaded at runtime in other Lua-based software.

In both cases, Ziglua will compile Lua from source and link against your Zig code making it easy to create software that integrates with Lua without requiring any system Lua libraries.

Ziglua `main` is kept up to date with Zig `master`. See the [`zig-0.13.0`](https://github.com/natecraddock/ziglua/tree/zig-0.13.0) branch for Zig 0.13.0 support.

## Documentation
Docs are a work in progress and are automatically generated. Most functions and public declarations are documented:
* [Ziglua Docs](https://natecraddock.github.io/ziglua/#ziglua.lib.Lua)

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
* Comptime convenience functions to make binding creation easier

Nearly every function in the C API is exposed in Ziglua. Additional convenience functions like `toAny` and `pushAny` use comptime reflection to make the API easier to use.

## Integrating Ziglua in your project

Run `zig fetch --save git+https://github.com/natecraddock/ziglua` to add the most recent commit of ziglua to your `build.zig.zon` file.

Add a `#<tag>` to the url to use a specific tagged release or commit like `zig fetch --save git+https://github.com/natecraddock/ziglua#0.3.0`

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

There are currently three additional options that can be passed to `b.dependency()`:

* `.lang`: Set the Lua language to build and embed. Defaults to `.lua54`. Possible values are `.lua51`, `.lua52`, `.lua53`, `.lua54`, and `luau`.
* `.shared`: Defaults to `false` for embedding in a Zig program. Set to `true` to dynamically link the Lua source code (useful for creating shared modules).
* `luau_use_4_vector`: defaults to false. Set to true to use 4-vectors instead of the default 3-vector in Luau.

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
