const std = @import("std");

const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("src/ziglua.zig");
    link(b, tests, .{ .use_apicheck = true });
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run ziglua library tests");
    test_step.dependOn(&tests.step);
}

fn dir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const Options = struct {
    /// Defines the macro LUA_USE_APICHECK in debug builds
    use_apicheck: bool = false,
};

pub fn link(b: *Builder, step: *LibExeObjStep, options: Options) void {
    const lib = buildLua(b, step, options);
    step.linkLibrary(lib);
    step.linkLibC();
}

const lib_dir = "lib/lua-5.4.4/src/";

fn buildLua(b: *Builder, step: *LibExeObjStep, options: Options) *LibExeObjStep {
    const lib_path = std.fs.path.join(b.allocator, &.{ dir(), "src/ziglua.zig" }) catch unreachable;
    const lib = b.addStaticLibrary("lua", lib_path);
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

    inline for (lua_source_files) |file| {
        const path = std.fs.path.join(b.allocator, &.{ dir(), lib_dir ++ file }) catch unreachable;
        step.addCSourceFile(path, &flags);
    }

    return lib;
}

const lua_source_files = [_][]const u8{
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
