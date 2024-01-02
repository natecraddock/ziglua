const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub const LuaVersion = enum {
    lua_51,
    lua_52,
    lua_53,
    lua_54,
    luau,
};

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_version = b.option(LuaVersion, "version", "Lua API and library version") orelse .lua_54;
    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;

    // Zig module
    const ziglua = b.addModule("ziglua", .{
        .source_file = switch (lua_version) {
            .lua_51 => .{ .path = "src/ziglua-5.1/lib.zig" },
            .lua_52 => .{ .path = "src/ziglua-5.2/lib.zig" },
            .lua_53 => .{ .path = "src/ziglua-5.3/lib.zig" },
            .lua_54 => .{ .path = "src/ziglua-5.4/lib.zig" },
            .luau => .{ .path = "src/zigluau/lib.zig" },
        },
    });

    const lib = switch (lua_version) {
        .lua_51, .lua_52, .lua_53, .lua_54 => buildLua(b, target, optimize, lua_version, shared),
        .luau => buildLuau(b, target, optimize, shared),
    };

    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = switch (lua_version) {
            .lua_51 => .{ .path = "src/ziglua-5.1/tests.zig" },
            .lua_52 => .{ .path = "src/ziglua-5.2/tests.zig" },
            .lua_53 => .{ .path = "src/ziglua-5.3/tests.zig" },
            .lua_54 => .{ .path = "src/ziglua-5.4/tests.zig" },
            .luau => .{ .path = "src/zigluau/tests.zig" },
        },
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibrary(lib);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run ziglua tests");
    test_step.dependOn(&run_tests.step);

    // Examples
    const examples = [_]struct { []const u8, []const u8 }{
        .{ "interpreter", "examples/interpreter.zig" },
        .{ "zig-function", "examples/zig-fn.zig" },
    };

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example[0],
            .root_source_file = .{ .path = example[1] },
            .target = target,
            .optimize = optimize,
        });
        exe.addModule("ziglua", ziglua);
        exe.linkLibrary(lib);

        const artifact = b.addInstallArtifact(exe, .{});
        const exe_step = b.step(b.fmt("install-example-{s}", .{example[0]}), b.fmt("Install {s} example", .{example[0]}));
        exe_step.dependOn(&artifact.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step(b.fmt("run-example-{s}", .{example[0]}), b.fmt("Run {s} example", .{example[0]}));
        run_step.dependOn(&run_cmd.step);
    }
}

fn buildLua(b: *Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, lua_version: LuaVersion, shared: bool) *Step.Compile {
    const lib_opts = .{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .version = switch (lua_version) {
            .lua_51 => std.SemanticVersion{ .major = 5, .minor = 1, .patch = 5 },
            .lua_52 => std.SemanticVersion{ .major = 5, .minor = 2, .patch = 4 },
            .lua_53 => std.SemanticVersion{ .major = 5, .minor = 3, .patch = 6 },
            .lua_54 => std.SemanticVersion{ .major = 5, .minor = 4, .patch = 6 },
            else => unreachable,
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
        else => unreachable,
    };
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ lib_dir, "include" }) });

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
        else => unreachable,
    };
    for (lua_source_files) |file| {
        lib.addCSourceFile(.{ .file = .{ .path = b.pathJoin(&.{ lib_dir, file }) }, .flags = &flags });
    }
    lib.linkLibC();

    lib.installHeader(b.pathJoin(&.{ lib_dir, "lua.h" }), "lua/lua.h");
    lib.installHeader(b.pathJoin(&.{ lib_dir, "lualib.h" }), "lua/lualib.h");
    lib.installHeader(b.pathJoin(&.{ lib_dir, "lauxlib.h" }), "lua/lauxlib.h");
    lib.installHeader(b.pathJoin(&.{ lib_dir, "luaconf.h" }), "lua/luaconf.h");

    return lib;
}

/// Luau has diverged enough from Lua (C++, project structure, ...) that it is easier to separate the build logic
fn buildLuau(b: *Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode, shared: bool) *Step.Compile {
    const lib_opts = .{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 0, .minor = 607, .patch = 0 },
    };
    const lib = if (shared)
        b.addSharedLibrary(lib_opts)
    else
        b.addStaticLibrary(lib_opts);

    const lib_dir = "lib/luau/VM";
    lib.addIncludePath(.{ .path = "lib/luau/Common/include" });
    lib.addIncludePath(.{ .path = "lib/luau/Compiler/include" });
    lib.addIncludePath(.{ .path = "lib/luau/Ast/include" });
    lib.addIncludePath(.{ .path = b.pathJoin(&.{ lib_dir, "include" }) });

    const os_tag = target.os_tag orelse
        (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target.os.tag;
    _ = os_tag;

    const flags = [_][]const u8{
        "-DLUA_USE_LONGJMP=1",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
    };

    for (luau_source_files) |file| {
        lib.addCSourceFile(.{ .file = .{ .path = file }, .flags = &flags });
    }
    lib.addCSourceFile(.{ .file = .{ .path = "src/zigluau/luau.cpp" }, .flags = &flags });
    lib.linkLibCpp();

    lib.installHeader("lib/luau/VM/include/lua.h", "lua/lua.h");
    lib.installHeader("lib/luau/VM/include/lualib.h", "lua/lualib.h");
    lib.installHeader("lib/luau/VM/include/luaconf.h", "lua/luaconf.h");
    lib.installHeader("lib/luau/Compiler/include/luacode.h", "lua/luacode.h");

    return lib;
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

const luau_source_files = [_][]const u8{
    "lib/luau/Compiler/src/BuiltinFolding.cpp",
    "lib/luau/Compiler/src/Builtins.cpp",
    "lib/luau/Compiler/src/BytecodeBuilder.cpp",
    "lib/luau/Compiler/src/Compiler.cpp",
    "lib/luau/Compiler/src/ConstantFolding.cpp",
    "lib/luau/Compiler/src/CostModel.cpp",
    "lib/luau/Compiler/src/TableShape.cpp",
    "lib/luau/Compiler/src/Types.cpp",
    "lib/luau/Compiler/src/ValueTracking.cpp",
    "lib/luau/Compiler/src/lcode.cpp",

    "lib/luau/VM/src/lapi.cpp",
    "lib/luau/VM/src/laux.cpp",
    "lib/luau/VM/src/lbaselib.cpp",
    "lib/luau/VM/src/lbitlib.cpp",
    "lib/luau/VM/src/lbuffer.cpp",
    "lib/luau/VM/src/lbuflib.cpp",
    "lib/luau/VM/src/lbuiltins.cpp",
    "lib/luau/VM/src/lcorolib.cpp",
    "lib/luau/VM/src/ldblib.cpp",
    "lib/luau/VM/src/ldebug.cpp",
    "lib/luau/VM/src/ldo.cpp",
    "lib/luau/VM/src/lfunc.cpp",
    "lib/luau/VM/src/lgc.cpp",
    "lib/luau/VM/src/lgcdebug.cpp",
    "lib/luau/VM/src/linit.cpp",
    "lib/luau/VM/src/lmathlib.cpp",
    "lib/luau/VM/src/lmem.cpp",
    "lib/luau/VM/src/lnumprint.cpp",
    "lib/luau/VM/src/lobject.cpp",
    "lib/luau/VM/src/loslib.cpp",
    "lib/luau/VM/src/lperf.cpp",
    "lib/luau/VM/src/lstate.cpp",
    "lib/luau/VM/src/lstring.cpp",
    "lib/luau/VM/src/lstrlib.cpp",
    "lib/luau/VM/src/ltable.cpp",
    "lib/luau/VM/src/ltablib.cpp",
    "lib/luau/VM/src/ltm.cpp",
    "lib/luau/VM/src/ludata.cpp",
    "lib/luau/VM/src/lutf8lib.cpp",
    "lib/luau/VM/src/lvmexecute.cpp",
    "lib/luau/VM/src/lvmload.cpp",
    "lib/luau/VM/src/lvmutils.cpp",

    "lib/luau/Ast/src/Ast.cpp",
    "lib/luau/Ast/src/Confusables.cpp",
    "lib/luau/Ast/src/Lexer.cpp",
    "lib/luau/Ast/src/Location.cpp",
    "lib/luau/Ast/src/Parser.cpp",
    "lib/luau/Ast/src/StringUtils.cpp",
    "lib/luau/Ast/src/TimeTrace.cpp",
};
