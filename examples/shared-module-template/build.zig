const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const moduleLua = b.createModule(.{
        .root_source_file = b.path("./lua.zig"), // our module with source code
        .target = target,
        .optimize = .ReleaseFast,
    });

    const libraryLua = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "lualib", // the name of our source file (shared module) that we will import into lua
        .root_module = moduleLua,
    });

    // if you download the prebinaries files from https://luabinaries.sourceforge.net
    // from SourceForge `Home/5.4.2/Windows Libraries/Dynamic/lua-5.4.2_Win64_dll17_lib.zip`
    // you will see that the lua library is called `lua54.dll`, not `lua.dll`
    // by default ziglua imports `lua.dll`, and we want to change this behavior
    const library_name: []const u8 = "lua54";

    const lua_dep = b.dependency("zlua", .{
        .target = target,
        .optimize = .ReleaseFast,
        .lang = .lua54,
        .shared = true, // set to `true` to dynamically link the Lua source code (useful for creating shared modules)
        .library_name = library_name, // change lua library name for linkage
    });

    libraryLua.root_module.addImport("zlua", lua_dep.module("zlua"));

    b.installArtifact(libraryLua);
}
