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

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lang = b.option(Language, "lang", "Lua language version to build") orelse .lua54;
    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;
    const luau_use_4_vector = b.option(bool, "luau_use_4_vector", "Build Luau to use 4-vectors instead of the default 3-vector.") orelse false;
    const upstream = b.dependency(@tagName(lang), .{});

    if (lang == .luau and shared) {
        std.debug.panic("Luau does not support compiling or loading shared modules", .{});
    }

    // Zig module
    const ziglua = b.addModule("ziglua", .{
        .root_source_file = .{ .path = "src/lib.zig" },
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

    const lib = switch (lang) {
        .luajit => buildLuaJIT(b, target, optimize, upstream, shared),
        .luau => buildLuau(b, target, optimize, upstream, luau_use_4_vector),
        else => buildLua(b, target, optimize, upstream, lang, shared),
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
        .root_source_file = .{ .path = "src/tests.zig" },
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

    const docs = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
    });
    docs.root_module.addOptions("config", config);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = switch (lang) {
            .lua51 => "docs/lua51",
            .lua52 => "docs/lua52",
            .lua53 => "docs/lua53",
            .lua54 => "docs/lua54",
            .luajit => "docs/luajit",
            .luau => "docs/luau",
        },
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
        .dependency = upstream,
        .files = lua_source_files,
        .flags = &flags,
    });

    lib.linkLibC();

    installHeader(lib, upstream.path("src/lua.h"), "lua.h");
    installHeader(lib, upstream.path("src/lualib.h"), "lualib.h");
    installHeader(lib, upstream.path("src/lauxlib.h"), "lauxlib.h");
    installHeader(lib, upstream.path("src/luaconf.h"), "luaconf.h");

    return lib;
}

// The Build.Step.Compile.installHeader function isn't updated to work with LazyPath
// TODO: report as an issue to Zig (and possibly fix?)
fn installHeader(cs: *Build.Step.Compile, src_path: Build.LazyPath, dest_rel_path: []const u8) void {
    const b = cs.step.owner;
    const install_file = b.addInstallFileWithDir(src_path, .header, dest_rel_path);
    b.getInstallStep().dependOn(&install_file.step);
    cs.installed_headers.append(&install_file.step) catch @panic("OOM");
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
        .dependency = upstream,
        .files = &luau_source_files,
        .flags = &flags,
    });
    lib.addCSourceFile(.{ .file = .{ .path = "src/luau.cpp" }, .flags = &flags });
    lib.linkLibCpp();

    // It may not be as likely that other software links against Luau, but might as well expose these anyway
    installHeader(lib, upstream.path("VM/include/lua.h"), "lua.h");
    installHeader(lib, upstream.path("VM/include/lualib.h"), "lualib.h");
    installHeader(lib, upstream.path("VM/include/luaconf.h"), "luaconf.h");

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
        .dependency = upstream,
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
        .dependency = upstream,
        .files = &luajit_vm,
    });

    lib.root_module.sanitize_c = false;

    installHeader(lib, upstream.path("src/lua.h"), "lua.h");
    installHeader(lib, upstream.path("src/lualib.h"), "lualib.h");
    installHeader(lib, upstream.path("src/lauxlib.h"), "lauxlib.h");
    installHeader(lib, upstream.path("src/luaconf.h"), "luaconf.h");
    installHeader(lib, luajit_h, "luajit.h");

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
