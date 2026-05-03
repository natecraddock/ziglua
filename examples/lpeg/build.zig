const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlua_dep = b.dependency("zlua", .{});
    const lpeg_dep = b.dependency("lpeg", .{});

    // Create a Zig module that depends on zlua.
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zlua", .module = zlua_dep.module("zlua") },
        },
    });

    // Also add the LPeg sources. Because we added zlua as an import, mod is already
    // linked against lua.
    for (source_files) |file| {
        mod.addCSourceFile(.{ .file = lpeg_dep.path(file) });
    }
    mod.addIncludePath(lpeg_dep.path(""));
    // This ensures that lua.h and other Lua headers can be found by LPeg.
    mod.addIncludePath(zlua_dep.artifact("lua").getEmittedIncludeTree());

    // Linking lua also works to add the header path, but since the zlua module is already imported
    // it is technically slightly redundant (but has the same result in the end).
    // mod.linkLibrary(zlua_dep.artifact("lua"));

    const exe = b.addExecutable(.{
        .name = "lpeg-example",
        .root_module = mod,
    });

    b.installArtifact(exe);
}

const source_files = [_][]const u8{
    "lpcap.c",
    "lpcode.c",
    "lpcset.c",
    "lpprint.c",
    "lptree.c",
    "lpvm.c",
};
