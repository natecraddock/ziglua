//! Run Luau bytecode

// How to recompile `test.luau.bin` bytecode binary:
//
//   luau-compile --binary test.luau  > test.bc
//
// This may be required if the Luau version gets upgraded.

const std = @import("std");

// The zlua module is made available in build.zig
const zlua = @import("zlua");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize The Lua vm and get a reference to the main thread
    //
    // Passing a Zig allocator to the Lua state requires a stable pointer
    var lua = try zlua.Lua.init(allocator);
    defer lua.deinit();

    // Open all Lua standard libraries
    lua.openLibs();

    // Load bytecode
    const src = @embedFile("./test.luau");
    const bc = try zlua.compile(allocator, src, zlua.CompileOptions{});
    defer allocator.free(bc);

    try lua.loadBytecode("...", bc);
    try lua.protectedCall(.{});
}
