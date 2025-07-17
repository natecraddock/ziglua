const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;

fn add(L: *Lua) i32 {
    const arg = L.toInteger(1) catch 0;

    std.debug.print("Argument from Lua: {}\n", .{arg});

    L.pushInteger(arg + 1);

    return 1;
}

fn module(lua: *Lua) i32 {
    const functions = [_]zlua.FnReg{
        zlua.FnReg{ .name = "add", .func = zlua.wrap(add) },
    };

    Lua.newLib(lua, &functions);

    return 1;
}

comptime {
    _ = zlua.exportFn("lualib", module);
}
