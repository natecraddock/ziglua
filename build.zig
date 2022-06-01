const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("src/zlua.zig");
    link(b, tests);
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run zlua library tests");
    test_step.dependOn(&tests.step);
}

fn dir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn link(b: *std.build.Builder, step: *std.build.LibExeObjStep) void {
    const lib = buildLua(b, step);
    step.linkLibrary(lib);
    step.linkLibC();
}

const lib_dir = "lib/lua-5.4.4/src/";

fn buildLua(b: *std.build.Builder, step: *std.build.LibExeObjStep) *std.build.LibExeObjStep {
    const lib_path = std.fs.path.join(b.allocator, &.{ dir(), "src/zlua.zig" }) catch unreachable;
    const lib = b.addStaticLibrary("lua", lib_path);
    lib.setBuildMode(step.build_mode);
    lib.setTarget(step.target);

    step.addIncludeDir(std.fs.path.join(b.allocator, &.{ dir(), lib_dir }) catch unreachable);

    const target = (std.zig.system.NativeTargetInfo.detect(b.allocator, lib.target) catch unreachable).target;
    const flags = switch (target.os.tag) {
        .linux => [_][]const u8{
            "-std=gnu99",
            "-DLUA_USE_LINUX",
        },
        .macos => [_][]const u8{
            "-std=gnu99",
            "-DLUA_USE_MACOSX",
        },
        .windows => [_][]const u8{
            "-std=gnu99",
            "-DLUA_USE_WINDOWS",
        },
        else => [_][]const u8{
            "-std=gnu99",
            "-DLUA_USE_POSIX",
        },
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
