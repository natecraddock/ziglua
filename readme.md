# Ziglua

[![shield showing current tests status](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml/badge.svg)](https://github.com/natecraddock/ziglua/actions/workflows/tests.yml)

A Zig module that provides a complete and lightweight wrapper around the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4). Ziglua currently supports the latest releases of Lua 5.1, 5.2, 5.3, and 5.4 and targets Zig master. The [`zig-0.10.0`](https://github.com/natecraddock/ziglua/tree/zig-0.10.0) branch supports the latest stable Zig, but will only be updated with bugfixes.

Ziglua can be used in two ways, either
* **embedded** to statically embed the Lua VM in a Zig program,
* or as a shared **module** to create Lua libraries that can be loaded at runtime in other Lua-based software.

In both cases, Ziglua will compile Lua from source and link against your Zig code making it easy to create software that integrates with Lua without requiring any system Lua libraries.

Like the Lua C API, the Ziglua API "emphasizes flexibility and simplicity... common tasks may involve several API calls. This may be boring, but it gives us full control over all the details" (_Programming In Lua 4th Edition_). However, Ziglua takes advantage of Zig's features to make it easier and safer to interact with the Lua API.

* [Docs](https://github.com/natecraddock/ziglua/blob/main/docs.md)
* [Examples](https://github.com/natecraddock/ziglua/blob/main/docs.md#examples)
* [Changelog](https://github.com/natecraddock/ziglua/blob/main/changelog.md)

## Why use Ziglua?

In a nutshell, Ziglua is a simple wrapper around the C API you would get by using Zig's `@cImport()`. Ziglua aims to mirror the [Lua C API](https://www.lua.org/manual/5.4/manual.html#4) as closely as possible, while improving ergonomics using Zig's features. For example:

* Zig error unions to require failure state handling
* Null-terminated slices instead of C strings
* Type-checked enums for parameters and return values
* Compiler-enforced checking of optional pointers
* Better types in many cases (e.g. `bool` instead of `int`)

While there are some helper functions added to complement the C API, Ziglua aims to remain low-level. This allows full access to the Lua API through a layer of Zig's improvements over C.

### Status

The API and tests for all versions of Lua are complete. Documentation is work in progress.

|         | API | Tests | Docs |
| ------- | --- | ----- | ---- |
| Lua 5.1 | ✓   | ✓     | ✓    |
| Lua 5.2 | ✓   | ✓     | ✓    |
| Lua 5.3 | ✓   | ✓     | ✓    |
| Lua 5.4 | ✓   | ✓     | ✓    |

I first implemented the Lua 5.4 API, then copied the code and edited for the other Lua versions. I have done my best to ensure accuracy, but if you find any errors please submit an issue or a pull request!

## Getting Started

First create a `build.zig.zon` file in your Zig project if you do not already have one. Add a ziglua dependency.

```
.{
	.name = "myproject",
	.version = "0.0.1",
	.dependencies = .{
		.ziglua = .{
			.url = "https://github.com/natecraddock/ziglua/archive/718083d3948fef791221bd2adbeed48b6c2399b4.tar.gz",
			.hash = "12205b564df959a94bcedc3e03b951f790cd96fbd7346578811f920b95d84cefe205",
		},
	}
}
```

Then in your `build.zig` file create and use the dependency

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

See [docs.md](https://github.com/natecraddock/ziglua/blob/main/docs.md) for documentation and detailed [examples](https://github.com/natecraddock/ziglua/blob/main/docs.md#examples) of using Ziglua.

## Contributing

Please make suggestions, report bugs, and create pull requests. Anyone is welcome to contribute!

I only use a subset of the Lua API through Ziglua, so if there are parts that aren't easy to use or understand, please fix it or let me know!

## Acknowledgements

Thanks to the following sources:

* [zoltan](https://github.com/ranciere/zoltan) for insights into compiling Lua with Zig
* [zig-autolua](https://github.com/daurnimator/zig-autolua) for help on writing an alloc function
* [mach-glfw](https://github.com/hexops/mach-glfw) for inspiration on a clean `build.zig`

And finally [Lua](https://lua.org). Thank you to the Lua team for creating and sharing such a great language!
