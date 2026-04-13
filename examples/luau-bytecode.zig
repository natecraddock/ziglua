//! Run Luau bytecode

// How to recompile `test.luau.bin` bytecode binary:
//
//   luau-compile --binary test.luau  > test.bc
//
// This may be required if the Luau version gets upgraded.

const std = @import("std");

// The zlua module is made available in build.zig
const zlua = @import("zlua");

pub fn main(init: std.process.Init) anyerror!void {
    const gpa = init.gpa;

    // Initialize The Lua vm and get a reference to the main thread
    //
    // Passing a Zig allocator to the Lua state requires a stable pointer
    var lua = try zlua.Lua.init(gpa);
    defer lua.deinit();

    // Open all Lua standard libraries
    lua.openLibs();

    // Load bytecode
    const src = @embedFile("./test.luau");
    const bc = try zlua.compile(gpa, src, zlua.CompileOptions{});
    defer gpa.free(bc);

    try lua.loadBytecode("...", bc);
    try lua.protectedCall(.{});
}
