const std = @import("std");

const Build = std.Build;

pub const LuaVersion = enum {
    lua_51,
    lua_52,
    lua_53,
    lua_54,
    // lua_jit,
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_version = b.option(LuaVersion, "version", "Lua API and library version") orelse .lua_54;
    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;

    // Zig module
    _ = b.addModule("ziglua", .{
        .source_file = switch (lua_version) {
            .lua_51 => .{ .path = "src/ziglua-5.1/lib.zig" },
            .lua_52 => .{ .path = "src/ziglua-5.2/lib.zig" },
            .lua_53 => .{ .path = "src/ziglua-5.3/lib.zig" },
            .lua_54 => .{ .path = "src/ziglua-5.4/lib.zig" },
        },
    });

    // Lua library artifact
    const lib_opts = .{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .version = switch (lua_version) {
            .lua_51 => std.SemanticVersion{ .major = 5, .minor = 1, .patch = 5 },
            .lua_52 => std.SemanticVersion{ .major = 5, .minor = 2, .patch = 4 },
            .lua_53 => std.SemanticVersion{ .major = 5, .minor = 3, .patch = 6 },
            .lua_54 => std.SemanticVersion{ .major = 5, .minor = 4, .patch = 4 },
        },
    };
    const lib = if (shared)
        b.addSharedLibrary(lib_opts)
    else
        b.addStaticLibrary(lib_opts);

    const lib_dir = switch (lua_version) {
        .lua_51 => "lib/lua-5.1/src",
        .lua_52 => "lib/lua-5.2/src",
        .lua_53 => "lib/lua-5.3/src",
        .lua_54 => "lib/lua-5.4/src",
    };
    lib.addIncludePath(.{ .path = lib_dir });

    const os_tag = target.os_tag orelse
        (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target.os.tag;

    const flags = [_][]const u8{
        // Standard version used in Lua Makefile
        "-std=gnu99",

        // Define target-specific macro
        switch (os_tag) {
            .linux => "-DLUA_USE_LINUX",
            .macos => "-DLUA_USE_MACOSX",
            .windows => "-DLUA_USE_WINDOWS",
            else => "-DLUA_USE_POSIX",
        },

        // Enable api check
        if (optimize == .Debug) "-DLUA_USE_APICHECK" else "",
    };

    const lua_source_files = switch (lua_version) {
        .lua_51 => &lua_51_source_files,
        .lua_52 => &lua_52_source_files,
        .lua_53 => &lua_53_source_files,
        .lua_54 => &lua_54_source_files,
    };
    for (lua_source_files) |file| {
        const path = std.fs.path.join(b.allocator, &.{ lib_dir, file }) catch unreachable;
        lib.addCSourceFile(.{ .file = .{ .path = path }, .flags = &flags });
    }
    lib.linkLibC();

    lib.installHeader(b.pathJoin(&.{ lib_dir, "lua.h" }), "lua/lua.h");
    lib.installHeader(b.pathJoin(&.{ lib_dir, "lualib.h" }), "lua/lualib.h");
    lib.installHeader(b.pathJoin(&.{ lib_dir, "lauxlib.h" }), "lua/lauxlib.h");
    lib.installHeader(b.pathJoin(&.{ lib_dir, "luaconf.h" }), "lua/luaconf.h");

    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = switch (lua_version) {
            .lua_51 => .{ .path = "src/ziglua-5.1/tests.zig" },
            .lua_52 => .{ .path = "src/ziglua-5.2/tests.zig" },
            .lua_53 => .{ .path = "src/ziglua-5.3/tests.zig" },
            .lua_54 => .{ .path = "src/ziglua-5.4/tests.zig" },
        },
        .optimize = optimize,
    });
    tests.addIncludePath(.{ .path = lib_dir });
    tests.linkLibrary(lib);

    const test_step = b.step("test", "Run ziglua tests");
    test_step.dependOn(&tests.step);
}

const lua_51_source_files = [_][]const u8{
    "lapi.c",
    "lcode.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
    "lauxlib.c",
    "lbaselib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loslib.c",
    "ltablib.c",
    "lstrlib.c",
    "loadlib.c",
    "linit.c",
};

const lua_52_source_files = [_][]const u8{
    "lapi.c",
    "lcode.c",
    "lctype.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
    "lauxlib.c",
    "lbaselib.c",
    "lbitlib.c",
    "lcorolib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loslib.c",
    "lstrlib.c",
    "ltablib.c",
    "loadlib.c",
    "linit.c",
};

const lua_53_source_files = [_][]const u8{
    "lapi.c",
    "lcode.c",
    "lctype.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
    "lauxlib.c",
    "lbaselib.c",
    "lbitlib.c",
    "lcorolib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loslib.c",
    "lstrlib.c",
    "ltablib.c",
    "lutf8lib.c",
    "loadlib.c",
    "linit.c",
};

const lua_54_source_files = [_][]const u8{
    "lapi.c",
    "lcode.c",
    "lctype.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
    "lauxlib.c",
    "lbaselib.c",
    "lcorolib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loadlib.c",
    "loslib.c",
    "lstrlib.c",
    "ltablib.c",
    "lutf8lib.c",
    "linit.c",
};
