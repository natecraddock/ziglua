const std = @import("std");

const zlua = @import("zlua");

// Because lpeg, like most Lua modules, is intended to be compiled to a shared library
// and imported with "require", it doesn’t expose the luaopen_lpeg function in a public header.
extern fn luaopen_lpeg(state: ?*zlua.LuaState) c_int;

pub fn main(init: std.process.Init) !void {
    var lua: *zlua.Lua = try .init(init.gpa);
    defer lua.deinit();

    // Ensure print() is available.
    lua.openLibs();

    // Also load the lpeg library and save in the global "lpeg".
    // This would typically be done by running require "lpeg" in a Lua script.
    _ = luaopen_lpeg(@ptrCast(lua));
    lua.setGlobal("lpeg");

    try lua.doString(
        \\-- example from https://www.inf.puc-rio.br/~roberto/lpeg/#ex
        \\-- matches a word followed by end-of-string
        \\p = lpeg.R"az"^1 * -1
        \\
        \\print(p:match("hello"))        --> 6
        \\print(lpeg.match(p, "hello"))  --> 6
        \\print(p:match("1 hello"))      --> nil
    );
}
