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
    const library_name = b.option([]const u8, "library_name", "Library name for lua linking, default is `lua`") orelse "lua";
    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;
    const luau_use_4_vector = b.option(bool, "luau_use_4_vector", "Build Luau to use 4-vectors instead of the default 3-vector.") orelse false;
    const lua_user_h = b.option(Build.LazyPath, "lua_user_h", "Lazy path to user supplied c header file") orelse null;

    if (lang == .luau and shared) {
        std.debug.panic("Luau does not support compiling or loading shared modules", .{});
    }

    if (lua_user_h != null and (lang == .luajit or lang == .luau)) {
        std.debug.panic("Only basic lua supports a user provided header file", .{});
    }

    // Zig module
    const zlua = b.addModule("zlua", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    // Expose build configuration to the ziglua module
    const config = b.addOptions();
    config.addOption(Language, "lang", lang);
    config.addOption(bool, "luau_use_4_vector", luau_use_4_vector);
    zlua.addOptions("config", config);

    if (lang == .luau) {
        const vector_size: usize = if (luau_use_4_vector) 4 else 3;
        zlua.addCMacro("LUA_VECTOR_SIZE", b.fmt("{}", .{vector_size}));
    }

    if (b.lazyDependency(@tagName(lang), .{})) |upstream| {
        const lib = switch (lang) {
            .luajit => luajit_setup.configure(b, target, optimize, upstream, shared),
            .luau => luau_setup.configure(b, target, optimize, upstream, luau_use_4_vector),
            else => lua_setup.configure(b, target, optimize, upstream, lang, shared, library_name, lua_user_h),
        };

        // Expose the Lua artifact, and get an install step that header translation can refer to
        const install_lib = b.addInstallArtifact(lib, .{});
        b.getInstallStep().dependOn(&install_lib.step);

        switch (lang) {
            .luau => {
                zlua.addIncludePath(upstream.path("Common/include"));
                zlua.addIncludePath(upstream.path("Compiler/include"));
                zlua.addIncludePath(upstream.path("Ast/include"));
                zlua.addIncludePath(upstream.path("VM/include"));
            },
            else => zlua.addIncludePath(upstream.path("src")),
        }

        zlua.linkLibrary(lib);

        // lib must expose all headers included by these root headers
        const c_header_path = switch (lang) {
            .luajit => b.path("build/include/luajit_all.h"),
            .luau => b.path("build/include/luau_all.h"),
            else => b.path("build/include/lua_all.h"),
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

        zlua.addImport("c", ziglua_c);
    }

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zlua", zlua);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run ziglua tests");
    test_step.dependOn(&run_tests.step);

    // Examples
    var common_examples = [_]struct { []const u8, []const u8 }{
        .{ "interpreter", "examples/interpreter.zig" },
        .{ "zig-function", "examples/zig-fn.zig" },
        .{ "multithreaded", "examples/multithreaded.zig" },
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
        exe.root_module.addImport("zlua", zlua);

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
    def_exe.root_module.addImport("zlua", zlua);
    var run_def_exe = b.addRunArtifact(def_exe);
    run_def_exe.addFileArg(b.path("definitions.lua"));

    const define_step = b.step("define", "Generate definitions.lua file");
    define_step.dependOn(&run_def_exe.step);
}
