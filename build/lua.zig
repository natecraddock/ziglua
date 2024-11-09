const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub const Language = enum {
    lua51,
    lua52,
    lua53,
    lua54,
    luajit,
    luau,
};

pub fn configure(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, lang: Language, shared: bool) *Step.Compile {
    const version = switch (lang) {
        .lua51 => std.SemanticVersion{ .major = 5, .minor = 1, .patch = 5 },
        .lua52 => std.SemanticVersion{ .major = 5, .minor = 2, .patch = 4 },
        .lua53 => std.SemanticVersion{ .major = 5, .minor = 3, .patch = 6 },
        .lua54 => std.SemanticVersion{ .major = 5, .minor = 4, .patch = 6 },
        else => unreachable,
    };

    const lib = if (shared)
        b.addSharedLibrary(.{
            .name = "lua",
            .target = target,
            .optimize = optimize,
            .version = version,
        })
    else
        b.addStaticLibrary(.{
            .name = "lua",
            .target = target,
            .optimize = optimize,
            .version = version,
        });

    lib.addIncludePath(upstream.path("src"));

    const flags = [_][]const u8{
        // Standard version used in Lua Makefile
        "-std=gnu99",

        // Define target-specific macro
        switch (target.result.os.tag) {
            .linux => "-DLUA_USE_LINUX",
            .macos => "-DLUA_USE_MACOSX",
            .windows => "-DLUA_USE_WINDOWS",
            else => "-DLUA_USE_POSIX",
        },

        // Enable api check
        if (optimize == .Debug) "-DLUA_USE_APICHECK" else "",
    };

    const lua_source_files = switch (lang) {
        .lua51 => &lua_base_source_files,
        .lua52 => &lua_52_source_files,
        .lua53 => &lua_53_source_files,
        .lua54 => &lua_54_source_files,
        else => unreachable,
    };

    lib.addCSourceFiles(.{
        .root = .{ .dependency = .{
            .dependency = upstream,
            .sub_path = "",
        } },
        .files = lua_source_files,
        .flags = &flags,
    });

    lib.linkLibC();

    lib.installHeader(upstream.path("src/lua.h"), "lua.h");
    lib.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    lib.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");
    lib.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");

    return lib;
}

const lua_base_source_files = [_][]const u8{
    "src/lapi.c",
    "src/lcode.c",
    "src/ldebug.c",
    "src/ldo.c",
    "src/ldump.c",
    "src/lfunc.c",
    "src/lgc.c",
    "src/llex.c",
    "src/lmem.c",
    "src/lobject.c",
    "src/lopcodes.c",
    "src/lparser.c",
    "src/lstate.c",
    "src/lstring.c",
    "src/ltable.c",
    "src/ltm.c",
    "src/lundump.c",
    "src/lvm.c",
    "src/lzio.c",
    "src/lauxlib.c",
    "src/lbaselib.c",
    "src/ldblib.c",
    "src/liolib.c",
    "src/lmathlib.c",
    "src/loslib.c",
    "src/ltablib.c",
    "src/lstrlib.c",
    "src/loadlib.c",
    "src/linit.c",
};

const lua_52_source_files = lua_base_source_files ++ [_][]const u8{
    "src/lctype.c",
    "src/lbitlib.c",
    "src/lcorolib.c",
};

const lua_53_source_files = lua_base_source_files ++ [_][]const u8{
    "src/lctype.c",
    "src/lbitlib.c",
    "src/lcorolib.c",
    "src/lutf8lib.c",
};

const lua_54_source_files = lua_base_source_files ++ [_][]const u8{
    "src/lctype.c",
    "src/lcorolib.c",
    "src/lutf8lib.c",
};
