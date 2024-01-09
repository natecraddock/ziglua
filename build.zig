const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub const LuaVersion = enum {
    lua51,
    lua52,
    lua53,
    lua54,
    luau,
};

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_version = b.option(LuaVersion, "version", "Lua API and library version") orelse .lua54;
    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;

    const upstream = b.dependency(@tagName(lua_version), .{});

    // Zig module
    const ziglua = b.addModule("ziglua", .{
        .root_source_file = switch (lua_version) {
            .lua51 => .{ .path = "src/ziglua-5.1/lib.zig" },
            .lua52 => .{ .path = "src/ziglua-5.2/lib.zig" },
            .lua53 => .{ .path = "src/ziglua-5.3/lib.zig" },
            .lua54 => .{ .path = "src/ziglua-5.4/lib.zig" },
            .luau => .{ .path = "src/zigluau/lib.zig" },
        },
    });

    const lib = switch (lua_version) {
        .luau => buildLuau(b, target, optimize, shared),
        else => buildLua(b, target, optimize, upstream, lua_version, shared),
    };

    ziglua.addIncludePath(upstream.path("src"));
    ziglua.linkLibrary(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = switch (lua_version) {
            .lua51 => .{ .path = "src/ziglua-5.1/tests.zig" },
            .lua52 => .{ .path = "src/ziglua-5.2/tests.zig" },
            .lua53 => .{ .path = "src/ziglua-5.3/tests.zig" },
            .lua54 => .{ .path = "src/ziglua-5.4/tests.zig" },
            .luau => .{ .path = "src/zigluau/tests.zig" },
        },
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("ziglua", ziglua);

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
        exe.root_module.addImport("ziglua", ziglua);

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

fn buildLua(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, lua_version: LuaVersion, shared: bool) *Step.Compile {

    const lib_opts = .{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .version = switch (lua_version) {
            .lua51 => std.SemanticVersion{ .major = 5, .minor = 1, .patch = 5 },
            .lua52 => std.SemanticVersion{ .major = 5, .minor = 2, .patch = 4 },
            .lua53 => std.SemanticVersion{ .major = 5, .minor = 3, .patch = 6 },
            .lua54 => std.SemanticVersion{ .major = 5, .minor = 4, .patch = 6 },
            else => unreachable,
        },
    };
    const lib = if (shared)
        b.addSharedLibrary(lib_opts)
    else
        b.addStaticLibrary(lib_opts);

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

    const lua_source_files = switch (lua_version) {
        .lua51 => &lua_51_source_files,
        .lua52 => &lua_52_source_files,
        .lua53 => &lua_53_source_files,
        .lua54 => &lua_54_source_files,
        else => unreachable,
    };
    for (lua_source_files) |file| {
        lib.addCSourceFile(.{ .file = upstream.path(file), .flags = &flags });
    }
    lib.linkLibC();

    return lib;
}

/// Luau has diverged enough from Lua (C++, project structure, ...) that it is easier to separate the build logic
fn buildLuau(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shared: bool) *Step.Compile {
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

    lib.installHeader("lib/luau/VM/include/lua.h", "lua.h");
    lib.installHeader("lib/luau/VM/include/lualib.h", "lualib.h");
    lib.installHeader("lib/luau/VM/include/luaconf.h", "luaconf.h");
    lib.installHeader("lib/luau/Compiler/include/luacode.h", "luacode.h");

    return lib;
}

const lua_51_source_files = [_][]const u8{
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

const lua_52_source_files = [_][]const u8{
    "src/lapi.c",
    "src/lcode.c",
    "src/lctype.c",
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
    "src/lbitlib.c",
    "src/lcorolib.c",
    "src/ldblib.c",
    "src/liolib.c",
    "src/lmathlib.c",
    "src/loslib.c",
    "src/lstrlib.c",
    "src/ltablib.c",
    "src/loadlib.c",
    "src/linit.c",
};

const lua_53_source_files = [_][]const u8{
    "src/lapi.c",
    "src/lcode.c",
    "src/lctype.c",
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
    "src/lbitlib.c",
    "src/lcorolib.c",
    "src/ldblib.c",
    "src/liolib.c",
    "src/lmathlib.c",
    "src/loslib.c",
    "src/lstrlib.c",
    "src/ltablib.c",
    "src/lutf8lib.c",
    "src/loadlib.c",
    "src/linit.c",
};

const lua_54_source_files = [_][]const u8{
    "src/lapi.c",
    "src/lcode.c",
    "src/lctype.c",
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
    "src/lcorolib.c",
    "src/ldblib.c",
    "src/liolib.c",
    "src/lmathlib.c",
    "src/loadlib.c",
    "src/loslib.c",
    "src/lstrlib.c",
    "src/ltablib.c",
    "src/lutf8lib.c",
    "src/linit.c",
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
