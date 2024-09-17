const std = @import("std");
const builtin = @import("builtin");
const OptimizeMode = std.builtin.OptimizeMode;

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

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};
    const emsdk = b.dependency("emsdk", .{});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_is_emscripten = target.result.os.tag == .emscripten;

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

    const lib = if (!target_is_emscripten) switch (lang) {
        .luajit => buildLuaJIT(b, target, optimize, upstream, shared),
        .luau => buildLuau(b, target, optimize, upstream, luau_use_4_vector),
        else => buildLua(b, target, optimize, upstream, lang, shared),
    } else switch (lang) {
        .luajit => @panic("LuaJIT is not supported on Emscripten"),
        .luau => buildLuauEmscripten(b, target, optimize, upstream, luau_use_4_vector, emsdk),
        else => buildLuaEmscripten(b, target, optimize, upstream, lang, emsdk),
    };

    // Expose the Lua artifact
    b.installArtifact(lib);

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
        if (!target_is_emscripten) {
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
        } else {
            const example_lib = b.addStaticLibrary(.{
                .name = example[0],
                .root_source_file = b.path(example[1]),
                .target = target,
                .optimize = optimize,
            });
            example_lib.linkLibC();
            example_lib.addIncludePath(b.path("src"));
            example_lib.root_module.addImport("ziglua", ziglua);

            // create a special emcc linker run step
            const link_step = try emLinkStep(b, .{
                .lib_main = example_lib,
                .target = target,
                .optimize = optimize,
                .emsdk = emsdk,
                .use_emmalloc = true,
                .use_filesystem = true,
                .shell_file_path = b.path("src/emscripten/shell.html"),
                .extra_args = &.{
                    "-sUSE_OFFSET_CONVERTER=1",
                    // this flag must either be present for both the compile and link steps, or be absent from both
                    "-fwasm-exceptions",
                },
            });
            // ...and a special run step to run the build result via emrun
            const run = emRunStep(b, .{
                .name = example[0],
                .emsdk = emsdk,
            });
            run.step.dependOn(&link_step.step);
            b.step(b.fmt("run-example-{s}", .{example[0]}), b.fmt("Run {s} example", .{example[0]})).dependOn(&run.step);
        }
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
}

fn buildLua(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, lang: Language, shared: bool) *Step.Compile {
    const lib_opts = .{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .version = switch (lang) {
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

fn buildLuaEmscripten(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    upstream: *Build.Dependency,
    lang: Language,
    emsdk: *Build.Dependency,
) *Step.Compile {
    const lib_opts = .{
        .name = "lua",
        .target = target,
        .optimize = optimize,
        .version = switch (lang) {
            .lua51 => std.SemanticVersion{ .major = 5, .minor = 1, .patch = 5 },
            .lua52 => std.SemanticVersion{ .major = 5, .minor = 2, .patch = 4 },
            .lua53 => std.SemanticVersion{ .major = 5, .minor = 3, .patch = 6 },
            .lua54 => std.SemanticVersion{ .major = 5, .minor = 4, .patch = 6 },
            else => unreachable,
        },
    };
    const lib = b.addStaticLibrary(lib_opts);

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

        "-I",
        upstream.path("src").getPath(b),

        // this flag must either be present for both the compile and link steps, or be absent from both
        "-fwasm-exceptions",
    };

    const lua_source_files = switch (lang) {
        .lua51 => &lua_base_source_files,
        .lua52 => &lua_52_source_files,
        .lua53 => &lua_53_source_files,
        .lua54 => &lua_54_source_files,
        else => unreachable,
    };

    for (lua_source_files) |file| {
        const compile_lua = emCompileStep(
            b,
            upstream.path(file),
            optimize,
            emsdk,
            &flags,
        );
        lib.addObjectFile(compile_lua);
    }

    lib.linkLibC();

    // unsure why this is necessary, but even with linkLibC() lauxlib.h will fail to find stdio.h
    lib.installHeader(b.path("src/emscripten/stdio.h"), "stdio.h");

    lib.installHeader(upstream.path("src/lua.h"), "lua.h");
    lib.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    lib.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");
    lib.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");

    return lib;
}

/// Luau has diverged enough from Lua (C++, project structure, ...) that it is easier to separate the build logic
fn buildLuau(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, luau_use_4_vector: bool) *Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 0, .minor = 607, .patch = 0 },
    });

    lib.addIncludePath(upstream.path("Common/include"));
    lib.addIncludePath(upstream.path("Compiler/include"));
    lib.addIncludePath(upstream.path("Ast/include"));
    lib.addIncludePath(upstream.path("VM/include"));

    const flags = [_][]const u8{
        "-DLUA_USE_LONGJMP=1",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
        if (luau_use_4_vector) "-DLUA_VECTOR_SIZE=4" else "",
    };

    lib.addCSourceFiles(.{
        .root = .{ .dependency = .{
            .dependency = upstream,
            .sub_path = "",
        } },
        .files = &luau_source_files,
        .flags = &flags,
    });
    lib.addCSourceFile(.{ .file = b.path("src/luau.cpp"), .flags = &flags });
    lib.linkLibCpp();

    // It may not be as likely that other software links against Luau, but might as well expose these anyway
    lib.installHeader(upstream.path("VM/include/lua.h"), "lua.h");
    lib.installHeader(upstream.path("VM/include/lualib.h"), "lualib.h");
    lib.installHeader(upstream.path("VM/include/luaconf.h"), "luaconf.h");

    return lib;
}

fn buildLuauEmscripten(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    upstream: *Build.Dependency,
    luau_use_4_vector: bool,
    emsdk: *Build.Dependency,
) *Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 0, .minor = 607, .patch = 0 },
        .link_libc = true,
    });

    const flags = .{
        "-DLUA_USE_LONGJMP=1",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
        // this flag must either be present for both the compile and link steps, or be absent from both
        "-fwasm-exceptions",
        if (luau_use_4_vector) "-DLUA_VECTOR_SIZE=4" else "-DLUA_VECTOR_SIZE=3",
        "-I",
        upstream.path("Common/include").getPath(b),
        "-I",
        upstream.path("Compiler/include").getPath(b),
        "-I",
        upstream.path("Ast/include").getPath(b),
        "-I",
        upstream.path("VM/include").getPath(b),
    };
    for (luau_source_files) |file| {
        const compile_luau = emCompileStep(
            b,
            upstream.path(file),
            optimize,
            emsdk,
            &flags,
        );
        lib.addObjectFile(compile_luau);
    }
    lib.addObjectFile(emCompileStep(
        b,
        b.path("src/luau.cpp"),
        optimize,
        emsdk,
        &flags,
    ));

    return lib;
}

fn buildLuaJIT(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, shared: bool) *Step.Compile {
    // TODO: extract this to the main build function because it is shared between all specialized build functions
    const lib_opts = .{
        .name = "lua",
        .target = target,
        .optimize = optimize,
    };
    const lib: *Step.Compile = if (shared)
        b.addSharedLibrary(lib_opts)
    else
        b.addStaticLibrary(lib_opts);

    // Compile minilua interpreter used at build time to generate files
    const minilua = b.addExecutable(.{
        .name = "minilua",
        .target = target, // TODO ensure this is the host
        .optimize = .ReleaseSafe,
    });
    minilua.linkLibC();
    minilua.root_module.sanitize_c = false;
    minilua.addCSourceFile(.{ .file = upstream.path("src/host/minilua.c") });

    // Generate the buildvm_arch.h file using minilua
    const dynasm_run = b.addRunArtifact(minilua);
    dynasm_run.addFileArg(upstream.path("dynasm/dynasm.lua"));

    // TODO: Many more flags to figure out
    if (target.result.cpu.arch.endian() == .little) {
        dynasm_run.addArgs(&.{ "-D", "ENDIAN_LE" });
    } else {
        dynasm_run.addArgs(&.{ "-D", "ENDIAN_BE" });
    }

    if (target.result.ptrBitWidth() == 64) dynasm_run.addArgs(&.{ "-D", "P64" });
    dynasm_run.addArgs(&.{ "-D", "JIT", "-D", "FFI" });

    if (target.result.abi.floatAbi() == .hard) {
        dynasm_run.addArgs(&.{ "-D", "FPU", "-D", "HFABI" });
    }

    if (target.result.os.tag == .windows) dynasm_run.addArgs(&.{ "-D", "WIN" });

    dynasm_run.addArg("-o");
    const buildvm_arch_h = dynasm_run.addOutputFileArg("buildvm_arch.h");

    dynasm_run.addFileArg(upstream.path(switch (target.result.cpu.arch) {
        .x86 => "src/vm_x86.dasc",
        .x86_64 => "src/vm_x64.dasc",
        .arm, .armeb => "src/vm_arm.dasc",
        .aarch64, .aarch64_be => "src/vm_arm64.dasc",
        .powerpc, .powerpcle => "src/vm_ppc.dasc",
        .mips, .mipsel => "src/vm_mips.dasc",
        .mips64, .mips64el => "src/vm_mips64.dasc",
        else => @panic("Unsupported architecture"),
    }));

    // Generate luajit.h using minilua
    const genversion_run = b.addRunArtifact(minilua);
    genversion_run.addFileArg(upstream.path("src/host/genversion.lua"));
    genversion_run.addFileArg(upstream.path("src/luajit_rolling.h"));
    genversion_run.addFileArg(upstream.path(".relver"));
    const luajit_h = genversion_run.addOutputFileArg("luajit.h");

    // Compile the buildvm executable used to generate other files
    const buildvm = b.addExecutable(.{
        .name = "buildvm",
        .target = target, // TODO ensure this is the host
        .optimize = .ReleaseSafe,
    });
    buildvm.linkLibC();
    buildvm.root_module.sanitize_c = false;

    // Needs to run after the buildvm_arch.h and luajit.h files are generated
    buildvm.step.dependOn(&dynasm_run.step);
    buildvm.step.dependOn(&genversion_run.step);

    buildvm.addCSourceFiles(.{
        .root = .{ .dependency = .{
            .dependency = upstream,
            .sub_path = "",
        } },
        .files = &.{ "src/host/buildvm_asm.c", "src/host/buildvm_fold.c", "src/host/buildvm_lib.c", "src/host/buildvm_peobj.c", "src/host/buildvm.c" },
    });

    buildvm.addIncludePath(upstream.path("src"));
    buildvm.addIncludePath(upstream.path("src/host"));
    buildvm.addIncludePath(buildvm_arch_h.dirname());
    buildvm.addIncludePath(luajit_h.dirname());

    // Use buildvm to generate files and headers used in the final vm
    const buildvm_bcdef = b.addRunArtifact(buildvm);
    buildvm_bcdef.addArgs(&.{ "-m", "bcdef", "-o" });
    const bcdef_header = buildvm_bcdef.addOutputFileArg("lj_bcdef.h");
    for (luajit_lib) |file| {
        buildvm_bcdef.addFileArg(upstream.path(file));
    }

    const buildvm_ffdef = b.addRunArtifact(buildvm);
    buildvm_ffdef.addArgs(&.{ "-m", "ffdef", "-o" });
    const ffdef_header = buildvm_ffdef.addOutputFileArg("lj_ffdef.h");
    for (luajit_lib) |file| {
        buildvm_ffdef.addFileArg(upstream.path(file));
    }

    const buildvm_libdef = b.addRunArtifact(buildvm);
    buildvm_libdef.addArgs(&.{ "-m", "libdef", "-o" });
    const libdef_header = buildvm_libdef.addOutputFileArg("lj_libdef.h");
    for (luajit_lib) |file| {
        buildvm_libdef.addFileArg(upstream.path(file));
    }

    const buildvm_recdef = b.addRunArtifact(buildvm);
    buildvm_recdef.addArgs(&.{ "-m", "recdef", "-o" });
    const recdef_header = buildvm_recdef.addOutputFileArg("lj_recdef.h");
    for (luajit_lib) |file| {
        buildvm_recdef.addFileArg(upstream.path(file));
    }

    const buildvm_folddef = b.addRunArtifact(buildvm);
    buildvm_folddef.addArgs(&.{ "-m", "folddef", "-o" });
    const folddef_header = buildvm_folddef.addOutputFileArg("lj_folddef.h");
    for (luajit_lib) |file| {
        buildvm_folddef.addFileArg(upstream.path(file));
    }

    const buildvm_ljvm = b.addRunArtifact(buildvm);
    buildvm_ljvm.addArg("-m");

    if (target.result.os.tag == .windows) {
        buildvm_ljvm.addArg("peobj");
    } else if (target.result.isDarwin()) {
        buildvm_ljvm.addArg("machasm");
    } else {
        buildvm_ljvm.addArg("elfasm");
    }

    buildvm_ljvm.addArg("-o");
    if (target.result.os.tag == .windows) {
        const ljvm_ob = buildvm_ljvm.addOutputFileArg("lj_vm. o");
        lib.addObjectFile(ljvm_ob);
    } else {
        const ljvm_asm = buildvm_ljvm.addOutputFileArg("lj_vm.S");
        lib.addAssemblyFile(ljvm_asm);
    }

    // Finally build LuaJIT after generating all the files
    lib.step.dependOn(&genversion_run.step);
    lib.step.dependOn(&buildvm_bcdef.step);
    lib.step.dependOn(&buildvm_ffdef.step);
    lib.step.dependOn(&buildvm_libdef.step);
    lib.step.dependOn(&buildvm_recdef.step);
    lib.step.dependOn(&buildvm_folddef.step);
    lib.step.dependOn(&buildvm_ljvm.step);

    lib.linkLibC();

    lib.defineCMacro("LUAJIT_UNWIND_EXTERNAL", null);
    lib.linkSystemLibrary("unwind");
    lib.root_module.unwind_tables = true;

    lib.addIncludePath(upstream.path("src"));
    lib.addIncludePath(luajit_h.dirname());
    lib.addIncludePath(bcdef_header.dirname());
    lib.addIncludePath(ffdef_header.dirname());
    lib.addIncludePath(libdef_header.dirname());
    lib.addIncludePath(recdef_header.dirname());
    lib.addIncludePath(folddef_header.dirname());

    lib.addCSourceFiles(.{
        .root = .{ .dependency = .{
            .dependency = upstream,
            .sub_path = "",
        } },
        .files = &luajit_vm,
    });

    lib.root_module.sanitize_c = false;

    lib.installHeader(upstream.path("src/lua.h"), "lua.h");
    lib.installHeader(upstream.path("src/lualib.h"), "lualib.h");
    lib.installHeader(upstream.path("src/lauxlib.h"), "lauxlib.h");
    lib.installHeader(upstream.path("src/luaconf.h"), "luaconf.h");
    lib.installHeader(luajit_h, "luajit.h");

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

const luajit_lib = [_][]const u8{
    "src/lib_base.c",
    "src/lib_math.c",
    "src/lib_bit.c",
    "src/lib_string.c",
    "src/lib_table.c",
    "src/lib_io.c",
    "src/lib_os.c",
    "src/lib_package.c",
    "src/lib_debug.c",
    "src/lib_jit.c",
    "src/lib_ffi.c",
    "src/lib_buffer.c",
};

const luajit_vm = luajit_lib ++ [_][]const u8{
    "src/lj_assert.c",
    "src/lj_gc.c",
    "src/lj_err.c",
    "src/lj_char.c",
    "src/lj_bc.c",
    "src/lj_obj.c",
    "src/lj_buf.c",
    "src/lj_str.c",
    "src/lj_tab.c",
    "src/lj_func.c",
    "src/lj_udata.c",
    "src/lj_meta.c",
    "src/lj_debug.c",
    "src/lj_prng.c",
    "src/lj_state.c",
    "src/lj_dispatch.c",
    "src/lj_vmevent.c",
    "src/lj_vmmath.c",
    "src/lj_strscan.c",
    "src/lj_strfmt.c",
    "src/lj_strfmt_num.c",
    "src/lj_serialize.c",
    "src/lj_api.c",
    "src/lj_profile.c",
    "src/lj_lex.c",
    "src/lj_parse.c",
    "src/lj_bcread.c",
    "src/lj_bcwrite.c",
    "src/lj_load.c",
    "src/lj_ir.c",
    "src/lj_opt_mem.c",
    "src/lj_opt_fold.c",
    "src/lj_opt_narrow.c",
    "src/lj_opt_dce.c",
    "src/lj_opt_loop.c",
    "src/lj_opt_split.c",
    "src/lj_opt_sink.c",
    "src/lj_mcode.c",
    "src/lj_snap.c",
    "src/lj_record.c",
    "src/lj_crecord.c",
    "src/lj_ffrecord.c",
    "src/lj_asm.c",
    "src/lj_trace.c",
    "src/lj_gdbjit.c",
    "src/lj_ctype.c",
    "src/lj_cdata.c",
    "src/lj_cconv.c",
    "src/lj_ccall.c",
    "src/lj_ccallback.c",
    "src/lj_carith.c",
    "src/lj_clib.c",
    "src/lj_cparse.c",
    "src/lj_lib.c",
    "src/lj_alloc.c",
    "src/lib_aux.c",
    "src/lib_init.c",
};

const luau_source_files = [_][]const u8{
    "Compiler/src/BuiltinFolding.cpp",
    "Compiler/src/Builtins.cpp",
    "Compiler/src/BytecodeBuilder.cpp",
    "Compiler/src/Compiler.cpp",
    "Compiler/src/ConstantFolding.cpp",
    "Compiler/src/CostModel.cpp",
    "Compiler/src/TableShape.cpp",
    "Compiler/src/Types.cpp",
    "Compiler/src/ValueTracking.cpp",
    "Compiler/src/lcode.cpp",

    "VM/src/lapi.cpp",
    "VM/src/laux.cpp",
    "VM/src/lbaselib.cpp",
    "VM/src/lbitlib.cpp",
    "VM/src/lbuffer.cpp",
    "VM/src/lbuflib.cpp",
    "VM/src/lbuiltins.cpp",
    "VM/src/lcorolib.cpp",
    "VM/src/ldblib.cpp",
    "VM/src/ldebug.cpp",
    "VM/src/ldo.cpp",
    "VM/src/lfunc.cpp",
    "VM/src/lgc.cpp",
    "VM/src/lgcdebug.cpp",
    "VM/src/linit.cpp",
    "VM/src/lmathlib.cpp",
    "VM/src/lmem.cpp",
    "VM/src/lnumprint.cpp",
    "VM/src/lobject.cpp",
    "VM/src/loslib.cpp",
    "VM/src/lperf.cpp",
    "VM/src/lstate.cpp",
    "VM/src/lstring.cpp",
    "VM/src/lstrlib.cpp",
    "VM/src/ltable.cpp",
    "VM/src/ltablib.cpp",
    "VM/src/ltm.cpp",
    "VM/src/ludata.cpp",
    "VM/src/lutf8lib.cpp",
    "VM/src/lvmexecute.cpp",
    "VM/src/lvmload.cpp",
    "VM/src/lvmutils.cpp",

    "Ast/src/Ast.cpp",
    "Ast/src/Confusables.cpp",
    "Ast/src/Lexer.cpp",
    "Ast/src/Location.cpp",
    "Ast/src/Parser.cpp",
    "Ast/src/StringUtils.cpp",
    "Ast/src/TimeTrace.cpp",
};

// for wasm32-emscripten, need to run the Emscripten linker from the Emscripten SDK
// NOTE: ideally this would go into a separate emsdk-zig package
pub const EmLinkOptions = struct {
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
    lib_main: *Build.Step.Compile, // the actual Zig code must be compiled to a static link library
    emsdk: *Build.Dependency,
    release_use_closure: bool = true,
    release_use_lto: bool = true,
    use_emmalloc: bool = false,
    use_filesystem: bool = true,
    shell_file_path: ?Build.LazyPath,
    extra_args: []const []const u8 = &.{},
};

pub fn emCompileStep(b: *Build, filename: Build.LazyPath, optimize: OptimizeMode, emsdk: *Build.Dependency, extra_flags: []const []const u8) Build.LazyPath {
    const emcc_path = emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "emcc" }).getPath(b);
    const emcc = b.addSystemCommand(&.{emcc_path});
    emcc.setName("emcc"); // hide emcc path
    emcc.addArg("-c");
    if (optimize == .ReleaseSmall) {
        emcc.addArg("-Oz");
    } else if (optimize == .ReleaseFast or optimize == .ReleaseSafe) {
        emcc.addArg("-O3");
    }
    emcc.addFileArg(filename);
    for (extra_flags) |flag| {
        emcc.addArg(flag);
    }
    emcc.addArg("-o");

    const output_name = switch (filename) {
        .dependency => filename.dependency.sub_path,
        .src_path => filename.src_path.sub_path,
        .cwd_relative => filename.cwd_relative,
        .generated => filename.generated.sub_path,
    };

    const output = emcc.addOutputFileArg(b.fmt("{s}.o", .{output_name}));
    return output;
}

pub fn emLinkStep(b: *Build, options: EmLinkOptions) !*Build.Step.InstallDir {
    const emcc_path = emSdkLazyPath(b, options.emsdk, &.{ "upstream", "emscripten", "emcc" }).getPath(b);
    const emcc = b.addSystemCommand(&.{emcc_path});
    emcc.setName("emcc"); // hide emcc path
    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
        if (options.release_use_lto) {
            emcc.addArg("-flto");
        }
        if (options.release_use_closure) {
            emcc.addArgs(&.{ "--closure", "1" });
        }
    }
    if (!options.use_filesystem) {
        emcc.addArg("-sNO_FILESYSTEM=1");
    }
    if (options.use_emmalloc) {
        emcc.addArg("-sMALLOC='emmalloc'");
    }
    if (options.shell_file_path) |shell_file_path| {
        emcc.addPrefixedFileArg("--shell-file=", shell_file_path);
    }
    for (options.extra_args) |arg| {
        emcc.addArg(arg);
    }

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    var it = options.lib_main.root_module.iterateDependencies(options.lib_main, false);
    while (it.next()) |item| {
        for (item.module.link_objects.items) |link_object| {
            switch (link_object) {
                .other_step => |compile_step| {
                    switch (compile_step.kind) {
                        .lib => {
                            emcc.addArtifactArg(compile_step);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    emcc.addArg("-o");
    const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{options.lib_main.name}));

    // the emcc linker creates 3 output files (.html, .wasm and .js)
    const install = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install.step.dependOn(&emcc.step);

    // get the emcc step to run on 'zig build'
    b.getInstallStep().dependOn(&install.step);
    return install;
}

// build a run step which uses the emsdk emrun command to run a build target in the browser
// NOTE: ideally this would go into a separate emsdk-zig package
pub const EmRunOptions = struct {
    name: []const u8,
    emsdk: *Build.Dependency,
};
pub fn emRunStep(b: *Build, options: EmRunOptions) *Build.Step.Run {
    const emrun_path = b.findProgram(&.{"emrun"}, &.{}) catch emSdkLazyPath(b, options.emsdk, &.{ "upstream", "emscripten", "emrun" }).getPath(b);
    const emrun = b.addSystemCommand(&.{ emrun_path, b.fmt("{s}/web/{s}.html", .{ b.install_path, options.name }) });
    return emrun;
}

// helper function to build a LazyPath from the emsdk root and provided path components
fn emSdkLazyPath(b: *Build, emsdk: *Build.Dependency, subPaths: []const []const u8) Build.LazyPath {
    return emsdk.path(b.pathJoin(subPaths));
}

fn createEmsdkStep(b: *Build, emsdk: *Build.Dependency) *Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emSdkLazyPath(b, emsdk, &.{"emsdk.bat"}).getPath(b)});
    } else {
        const step = b.addSystemCommand(&.{"bash"});
        step.addArg(emSdkLazyPath(b, emsdk, &.{"emsdk"}).getPath(b));
        return step;
    }
}

// One-time setup of the Emscripten SDK (runs 'emsdk install + activate'). If the
// SDK had to be setup, a run step will be returned which should be added
// as dependency to the sokol library (since this needs the emsdk in place),
// if the emsdk was already setup, null will be returned.
// NOTE: ideally this would go into a separate emsdk-zig package
// NOTE 2: the file exists check is a bit hacky, it would be cleaner
// to build an on-the-fly helper tool which takes care of the SDK
// setup and just does nothing if it already happened
// NOTE 3: this code works just fine when the SDK version is updated in build.zig.zon
// since this will be cloned into a new zig cache directory which doesn't have
// an .emscripten file yet until the one-time setup.
fn emSdkSetupStep(b: *Build, emsdk: *Build.Dependency) !?*Build.Step.Run {
    const dot_emsc_path = emSdkLazyPath(b, emsdk, &.{".emscripten"}).getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}
