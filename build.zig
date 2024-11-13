const std = @import("std");

const Build = std.Build;
pub const Language = lua_setup.Language;
const Step = std.Build.Step;

const lua_setup = @import("build/lua.zig");
const luau_setup = @import("build/luau.zig");
const luajit_setup = @import("build/luajit.zig");

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lang = b.option(Language, "lang", "Lua language version to build") orelse .lua54;
    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;
    const luau_use_4_vector = b.option(bool, "luau_use_4_vector", "Build Luau to use 4-vectors instead of the default 3-vector.") orelse false;

    if (lang == .luau and shared) {
        std.debug.panic("Luau does not support compiling or loading shared modules", .{});
    }

    // Zig module
    const ziglua = b.addModule("ziglua", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    // Expose build configuration to the ziglua module
    const config = b.addOptions();
    config.addOption(Language, "lang", lang);
    config.addOption(bool, "luau_use_4_vector", luau_use_4_vector);
    ziglua.addOptions("config", config);

    if (lang == .luau) {
        const vector_size: usize = if (luau_use_4_vector) 4 else 3;
        ziglua.addCMacro("LUA_VECTOR_SIZE", b.fmt("{}", .{vector_size}));
    }

    const upstream = b.dependency(@tagName(lang), .{});

    const lib = switch (lang) {
        .luajit => luajit_setup.configure(b, target, optimize, upstream, shared),
        .luau => luau_setup.configure(b, target, optimize, upstream, luau_use_4_vector),
        else => lua_setup.configure(b, target, optimize, upstream, lang, shared),
    };

    // Expose the Lua artifact, and get an install step that header translation can refer to
    const install_lib = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&install_lib.step);

    switch (lang) {
        .luau => {
            ziglua.addIncludePath(upstream.path("Common/include"));
            ziglua.addIncludePath(upstream.path("Compiler/include"));
            ziglua.addIncludePath(upstream.path("Ast/include"));
            ziglua.addIncludePath(upstream.path("VM/include"));
        },
        else => ziglua.addIncludePath(upstream.path("src")),
    }

    ziglua.linkLibrary(lib);

    // lib must expose all headers included by these root headers
    const c_header_path = switch (lang) {
        .luajit => b.path("include/luajit_all.h"),
        .luau => b.path("include/luau_all.h"),
        else => b.path("include/lua_all.h"),
    };
    const c_headers = b.addTranslateC(.{
        .root_source_file = c_header_path,
        .target = target,
        .optimize = optimize,
    });
    c_headers.addIncludePath(lib.getEmittedIncludeTree());
    c_headers.step.dependOn(&install_lib.step);

    const ziglua_c = b.addModule("ziglua-c", .{
        .root_source_file = c_headers.getOutput(),
        .target = c_headers.target,
        .optimize = c_headers.optimize,
        .link_libc = c_headers.link_libc,
    });

    ziglua.addImport("c", ziglua_c);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("ziglua", ziglua);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run ziglua tests");
    test_step.dependOn(&run_tests.step);

    // Examples
    var common_examples = [_]struct { []const u8, []const u8 }{
        .{ "interpreter", "examples/interpreter.zig" },
        .{ "zig-function", "examples/zig-fn.zig" },
    };
    const luau_examples = [_]struct { []const u8, []const u8 }{
        .{ "luau-bytecode", "examples/luau-bytecode.zig" },
    };
    const examples = if (lang == .luau) &common_examples ++ luau_examples else &common_examples;

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example[0],
            .root_source_file = b.path(example[1]),
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

    const docs = b.addObject(.{
        .name = "ziglua",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build and install the documentation");
    docs_step.dependOn(&install_docs.step);

    // definitions example
    const def_exe = b.addExecutable(.{
        .root_source_file = b.path("examples/define-exe.zig"),
        .name = "define-zig-types",
        .target = target,
    });
    def_exe.root_module.addImport("ziglua", ziglua);
    var run_def_exe = b.addRunArtifact(def_exe);
    run_def_exe.addFileArg(b.path("definitions.lua"));

    const define_step = b.step("define", "Generate definitions.lua file");
    define_step.dependOn(&run_def_exe.step);
}
