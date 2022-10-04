const std = @import("std");

const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

const LuaVersion = enum {
    lua_51,
    lua_52,
    lua_53,
    lua_54,
    lua_jit,
};

fn libPath(version: LuaVersion) []const u8 {
    return switch (version) {
        .lua_51 => "src/ziglua-5.1/lib.zig",
        .lua_52 => "src/ziglua-5.2/lib.zig",
        .lua_53 => "src/ziglua-5.3/lib.zig",
        .lua_54 => "src/ziglua-5.4/lib.zig",
        else => unreachable,
        // .lua_jit => "src/ziglua-jit/lib.zig",
    };
}

pub fn build(b: *Builder) void {
    const version = b.option(LuaVersion, "version", "lua version to test") orelse .lua_54;

    const tests = b.addTest(switch (version) {
        .lua_51 => "src/ziglua-5.1/tests.zig",
        .lua_52 => "src/ziglua-5.2/tests.zig",
        .lua_53 => "src/ziglua-5.3/tests.zig",
        .lua_54 => "src/ziglua-5.4/tests.zig",
        else => unreachable,
    });
    link(b, tests, libPath(version), .{ .use_apicheck = true, .version = version });

    const test_step = b.step("test", "Run ziglua library tests");
    test_step.dependOn(&tests.step);
}

fn dir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const Options = struct {
    /// Defines the macro LUA_USE_APICHECK in debug builds
    use_apicheck: bool = false,
    /// Defines the Lua version to build and link
    version: LuaVersion = .lua_54,
};

pub fn linkAndPackage(b: *Builder, step: *LibExeObjStep, options: Options) std.build.Pkg {
    const lib_path = libPath(options.version);
    link(b, step, lib_path, options);

    return .{
        .name = "ziglua",
        .path = .{ .path = std.fs.path.join(b.allocator, &.{ dir(), lib_path }) catch unreachable },
    };
}

// TODO: expose the link and package steps separately for advanced use cases?
fn link(b: *Builder, step: *LibExeObjStep, lib_path: []const u8, options: Options) void {
    const lib = buildLua(b, step, lib_path, options);
    step.linkLibrary(lib);
    step.linkLibC();
}

// TODO: how to test all versions? May need a make/help script to test all
// versions separately because there might be name collisions
fn buildLua(b: *Builder, step: *LibExeObjStep, lib_path: []const u8, options: Options) *LibExeObjStep {
    const lib_dir = switch (options.version) {
        .lua_51 => "lib/lua-5.1.5/src/",
        .lua_52 => "lib/lua-5.2.4/src/",
        .lua_53 => "lib/lua-5.3.6/src/",
        .lua_54 => "lib/lua-5.4.4/src/",
        else => unreachable,
        // .lua_jit => "lib/lua-5.4.4/src/",
    };

    const absolute_lib_path = std.fs.path.join(b.allocator, &.{ dir(), lib_path }) catch unreachable;
    const lib = b.addStaticLibrary("lua", absolute_lib_path);
    lib.setBuildMode(step.build_mode);
    lib.setTarget(step.target);

    const apicheck = step.build_mode == .Debug and options.use_apicheck;

    step.addIncludeDir(std.fs.path.join(b.allocator, &.{ dir(), lib_dir }) catch unreachable);

    const target = (std.zig.system.NativeTargetInfo.detect(b.allocator, lib.target) catch unreachable).target;

    const flags = [_][]const u8{
        // Standard version used in Lua Makefile
        "-std=gnu99",

        // Define target-specific macro
        switch (target.os.tag) {
            .linux => "-DLUA_USE_LINUX",
            .macos => "-DLUA_USE_MACOSX",
            .windows => "-DLUA_USE_WINDOWS",
            else => "-DLUA_USE_POSIX",
        },

        // Enable api check if desired
        if (apicheck) "-DLUA_USE_APICHECK" else "",
    };

    const lua_source_files = switch (options.version) {
        .lua_51 => &lua_51_source_files,
        .lua_52 => &lua_52_source_files,
        .lua_53 => &lua_53_source_files,
        .lua_54 => &lua_54_source_files,
        else => unreachable,
        // .lua_jit => &lua_jit_source_files,
    };

    for (lua_source_files) |file| {
        const path = std.fs.path.join(b.allocator, &.{ dir(), lib_dir, file }) catch unreachable;
        step.addCSourceFile(path, &flags);
    }

    return lib;
}

const lua_51_source_files = [_][]const u8 {
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

const lua_52_source_files = [_][]const u8 {
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
