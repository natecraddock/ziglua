const std = @import("std");
const testing = std.testing;

const ziglua = @import("ziglua");

const AllocFn = ziglua.AllocFn;
const Buffer = ziglua.Buffer;
const DebugInfo = ziglua.DebugInfo;
const Lua = ziglua.Lua;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

fn expectStringContains(actual: []const u8, expected_contains: []const u8) !void {
    if (std.mem.indexOf(u8, actual, expected_contains) == null) return;
    return error.TestExpectedStringContains;
}

// Helper functions
//
// For the most part, it is easy to test each Lua version simulataneously. Although each
// version offers a different API, there are more similarities than differences. Using
// ziglua.lang is usually enough to handle the differences. Some common functions like
// toInteger differ enough to require these helper functions to handle the differences
// to keep the test code more readable

/// Return true if ziglua.lang matches any of the given langs
inline fn langIn(langs: anytype) bool {
    inline for (langs) |lang| if (ziglua.lang == lang) return true;
    return false;
}

/// toInteger that always returns an error union
inline fn toInteger(lua: *Lua, index: i32) !ziglua.Integer {
    if (ziglua.lang == .lua51) {
        return lua.toInteger(index);
    } else return try lua.toInteger(index);
}

/// toNumber that always returns an error union
inline fn toNumber(lua: *Lua, index: i32) !ziglua.Number {
    if (ziglua.lang == .lua51) {
        return lua.toNumber(index);
    } else return try lua.toNumber(index);
}

/// getGlobal that always returns an error union
inline fn getGlobal(lua: *Lua, name: [:0]const u8) !ziglua.LuaType {
    if (ziglua.lang == .lua51 or ziglua.lang == .lua52) {
        lua.getGlobal(name);
        return lua.typeOf(-1);
    }
    return try lua.getGlobal(name);
}

/// getGlobal that always returns a LuaType
inline fn getIndex(lua: *Lua, index: i32, i: ziglua.Integer) ziglua.LuaType {
    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        return lua.getIndex(index, i);
    }
    _ = lua.rawGetIndex(index, i);
    return lua.typeOf(-1);
}

/// getTagle that always returns a LuaType
inline fn getTable(lua: *Lua, index: i32) ziglua.LuaType {
    if (langIn(.{ .lua53, .lua54, .luau })) {
        return lua.getTable(index);
    }
    lua.getTable(index);
    return lua.typeOf(-1);
}

/// rawGetTable that always returns a LuaType
inline fn rawGetTable(lua: *Lua, index: i32) ziglua.LuaType {
    if (langIn(.{ .lua53, .lua54, .luau })) {
        return lua.rawGetTable(index);
    }
    lua.rawGetTable(index);
    return lua.typeOf(-1);
}

/// pushFunction that sets the name for Luau
inline fn pushFunction(lua: *Lua, c_fn: ziglua.CFn) void {
    if (ziglua.lang == .luau) return lua.pushFunction(c_fn, "");
    lua.pushFunction(c_fn);
}

fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
    _ = data;

    const alignment = @alignOf(std.c.max_align_t);
    if (@as(?[*]align(alignment) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
        const prev_slice = prev_ptr[0..osize];
        if (nsize == 0) {
            testing.allocator.free(prev_slice);
            return null;
        }
        const new_ptr = testing.allocator.realloc(prev_slice, nsize) catch return null;
        return new_ptr.ptr;
    } else if (nsize == 0) {
        return null;
    } else {
        const new_ptr = testing.allocator.alignedAlloc(u8, alignment, nsize) catch return null;
        return new_ptr.ptr;
    }
}

fn failing_alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
    _ = data;
    _ = ptr;
    _ = osize;
    _ = nsize;
    return null;
}

test "initialization" {
    // initialize the Zig wrapper
    var lua = try Lua.init(testing.allocator);
    try expectEqual(ziglua.Status.ok, lua.status());
    lua.deinit();

    // attempt to initialize the Zig wrapper with no memory
    try expectError(error.Memory, Lua.init(testing.failing_allocator));

    // use the library directly
    lua = try Lua.newState(alloc, null);
    lua.close();

    // use the library with a bad AllocFn
    try expectError(error.Memory, Lua.newState(failing_alloc, null));

    // use the auxiliary library (uses libc realloc and cannot be checked for leaks!)
    lua = try Lua.newStateLibc();
    lua.close();
}

test "alloc functions" {
    var lua = try Lua.newState(alloc, null);
    defer lua.deinit();

    // get default allocator
    var data: *anyopaque = undefined;
    try expectEqual(alloc, lua.getAllocFn(&data));

    if (ziglua.lang != .luau) {
        // set a bad allocator
        lua.setAllocF(failing_alloc, null);
        try expectEqual(failing_alloc, lua.getAllocFn(&data));

        // reset the good one
        lua.setAllocF(alloc, null);
    }
}

test "standard library loading" {
    // open all standard libraries
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.openLibs();
    }

    // open a subset of standard libraries with Zig wrapper
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();

        switch (ziglua.lang) {
            .lua51 => lua.open(.{ .base = true, .package = true, .string = true, .table = true, .math = true, .io = true, .os = true, .debug = true }),
            .lua52 => lua.open(.{ .base = true, .coroutine = true, .package = true, .string = true, .table = true, .math = true, .io = true, .os = true, .debug = true, .bit = true }),
            .lua53, .lua54 => lua.open(.{ .base = true, .coroutine = true, .package = true, .string = true, .utf8 = true, .table = true, .math = true, .io = true, .os = true, .debug = true }),
            .luau => lua.open(.{ .base = true, .coroutine = true, .package = true, .string = true, .utf8 = true, .table = true, .math = true, .io = true, .os = true, .debug = true }),
        }
    }

    // open all standard libraries with individual functions
    // these functions are only useful if you want to load the standard
    // packages into a non-standard table
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();

        lua.openBase();
        lua.openString();
        lua.openTable();
        lua.openMath();
        lua.openOS();
        lua.openDebug();

        // TODO: why do these fail in lua51? Debugger shows it is on line with LUA_ENVIRONINDEX
        if (ziglua.lang != .luau and ziglua.lang != .lua51) {
            lua.openPackage();
            lua.openIO();
        }
        if (ziglua.lang != .lua51) lua.openCoroutine();
        if (ziglua.lang != .lua51 and ziglua.lang != .lua52) lua.openUtf8();
    }
}

test "arithmetic (lua_arith)" {
    if (!langIn(.{ .lua52, .lua53, .lua54 })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNumber(10);
    lua.pushNumber(42);

    lua.arith(.add);
    try expectEqual(52, try lua.toNumber(1));

    lua.pushNumber(12);
    lua.arith(.sub);
    try expectEqual(40, try lua.toNumber(1));

    lua.pushNumber(2);
    lua.arith(.mul);
    try expectEqual(80, try lua.toNumber(1));

    lua.pushNumber(8);
    lua.arith(.div);
    try expectEqual(10, try lua.toNumber(1));

    lua.pushNumber(3);
    lua.arith(.mod);
    try expectEqual(1, try lua.toNumber(1));

    lua.arith(.negate);
    try expectEqual(-1, try lua.toNumber(1));

    if (ziglua.lang == .lua52) return;

    lua.arith(.negate);
    lua.pushNumber(2);
    lua.arith(.shl);
    try expectEqual(4, try lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.shr);
    try expectEqual(2, try lua.toInteger(1));

    lua.pushNumber(4);
    lua.arith(.bor);
    try expectEqual(6, try lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.band);
    try expectEqual(0, try lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.bxor);
    try expectEqual(1, try lua.toInteger(1));

    lua.arith(.bnot); // 0xFFFFFFFFFFFFFFFE which is -2
    try expectEqual(-2, try lua.toInteger(1));

    lua.pushNumber(3);
    lua.arith(.pow);
    try expectEqual(-8, try lua.toInteger(1));

    lua.pushNumber(11);
    lua.pushNumber(2);
    lua.arith(.int_div);
    try expectEqual(5, try lua.toNumber(-1));
}

test "compare" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNumber(1);
    lua.pushNumber(2);

    if (langIn(.{ .lua52, .lua53, .lua54 })) {
        try expect(!lua.compare(-2, -1, .eq));
        try expect(!lua.compare(-1, -2, .le));
        try expect(!lua.compare(-1, -2, .lt));
        try expect(lua.compare(-2, -1, .le));
        try expect(lua.compare(-2, -1, .lt));

        try expect(!lua.rawEqual(-1, -2));
        lua.pushNumber(2);
        try expect(lua.rawEqual(-1, -2));
    } else {
        try testing.expect(!lua.equal(1, 2));
        try testing.expect(lua.lessThan(1, 2));

        lua.pushInteger(2);
        try testing.expect(lua.equal(2, 3));
    }
}

const add = struct {
    fn addInner(l: *Lua) i32 {
        const a = toInteger(l, 1) catch 0;
        const b = toInteger(l, 2) catch 0;
        l.pushInteger(a + b);
        return 1;
    }
}.addInner;

test "type of and getting values" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expect(lua.isNil(1));
    try expect(lua.isNoneOrNil(1));
    try expect(lua.isNoneOrNil(2));
    try expect(lua.isNone(2));
    try expectEqual(.nil, lua.typeOf(1));

    lua.pushBoolean(true);
    try expectEqual(.boolean, lua.typeOf(-1));
    try expect(lua.isBoolean(-1));

    lua.newTable();
    try expectEqual(.table, lua.typeOf(-1));
    try expect(lua.isTable(-1));

    lua.pushInteger(1);
    try expectEqual(.number, lua.typeOf(-1));
    try expect(lua.isNumber(-1));
    try expectEqual(1, try toInteger(&lua, -1));
    try expectEqualStrings("number", lua.typeNameIndex(-1));

    var value: i32 = 0;
    lua.pushLightUserdata(&value);
    try expectEqual(.light_userdata, lua.typeOf(-1));
    try expect(lua.isLightUserdata(-1));
    try expect(lua.isUserdata(-1));

    lua.pushNumber(0.1);
    try expectEqual(.number, lua.typeOf(-1));
    try expect(lua.isNumber(-1));
    try expectEqual(0.1, try toNumber(&lua, -1));

    _ = lua.pushThread();
    try expectEqual(.thread, lua.typeOf(-1));
    try expect(lua.isThread(-1));
    try expectEqual(lua.state, (try lua.toThread(-1)).state);

    _ = lua.pushString("all your codebase are belong to us");
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    if (ziglua.lang == .luau) lua.pushFunction(ziglua.wrap(add), "add") else lua.pushFunction(ziglua.wrap(add));
    try expectEqual(.function, lua.typeOf(-1));
    try expect(lua.isCFunction(-1));
    try expect(lua.isFunction(-1));
    try expectEqual(ziglua.wrap(add), try lua.toCFunction(-1));

    _ = lua.pushBytes("hello world");
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    _ = lua.pushFString("%s %s %d", .{ "hello", "world", @as(i32, 10) });
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));
    try expectEqualStrings("hello world 10", std.mem.span(try lua.toString(-1)));

    lua.pushValue(2);
    try expectEqual(.boolean, lua.typeOf(-1));
    try expect(lua.isBoolean(-1));
}

test "typenames" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectEqualStrings("no value", lua.typeName(.none));
    try expectEqualStrings("nil", lua.typeName(.nil));
    try expectEqualStrings("boolean", lua.typeName(.boolean));
    try expectEqualStrings("userdata", lua.typeName(.light_userdata));
    try expectEqualStrings("number", lua.typeName(.number));
    try expectEqualStrings("string", lua.typeName(.string));
    try expectEqualStrings("table", lua.typeName(.table));
    try expectEqualStrings("function", lua.typeName(.function));
    try expectEqualStrings("userdata", lua.typeName(.userdata));
    try expectEqualStrings("thread", lua.typeName(.thread));

    if (ziglua.lang == .luau) {
        try expectEqualStrings("vector", lua.typeName(.vector));
    }
}

test "unsigned" {
    if (ziglua.lang != .lua52) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushUnsigned(123456);
    try expectEqual(123456, try lua.toUnsigned(-1));

    _ = lua.pushBytes("hello");
    try expectError(error.Fail, lua.toUnsigned(-1));
}

test "executing string contents" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    try lua.loadString("f = function(x) return x + 10 end");
    try lua.protectedCall(0, 0, 0);
    try lua.loadString("a = f(2)");
    try lua.protectedCall(0, 0, 0);

    try expectEqual(.number, try getGlobal(&lua, "a"));
    try expectEqual(12, try toInteger(&lua, 1));

    try expectError(if (ziglua.lang == .luau) error.Fail else error.Syntax, lua.loadString("bad syntax"));
    try lua.loadString("a = g()");
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
}

test "filling and checking the stack" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectEqual(0, lua.getTop());

    // We want to push 30 values onto the stack
    // this should work without fail
    try lua.checkStack(30);

    var count: i32 = 0;
    while (count < 30) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(30, lua.getTop());

    // this should fail (beyond max stack size)
    try expectError(error.Fail, lua.checkStack(1_000_000));

    // this is small enough it won't fail (would raise an error if it did)
    lua.checkStackErr(40, null);
    while (count < 40) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(40, lua.getTop());
}

test "stack manipulation" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // TODO: combine these more
    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        var num: i32 = 1;
        while (num <= 10) : (num += 1) {
            lua.pushInteger(num);
        }
        try expectEqual(10, lua.getTop());

        lua.setTop(12);
        try expectEqual(12, lua.getTop());
        try expect(lua.isNil(-1));

        // rotate the two nils to the bottom of the stack
        lua.rotate(1, 2);
        try expect(lua.isNil(1));
        try expect(lua.isNil(2));

        lua.remove(2);
        try expect(lua.isNil(1));
        try expect(lua.isInteger(2));

        lua.insert(1);
        try expect(lua.isInteger(1));
        try expect(lua.isNil(2));

        lua.replace(2);
        try expect(lua.isInteger(2));
        try expectEqual(10, lua.getTop());

        lua.copy(1, 2);
        try expectEqual(10, try lua.toInteger(1));
        try expectEqual(10, try lua.toInteger(2));
        try expectEqual(1, try lua.toInteger(3));
        try expectEqual(8, try lua.toInteger(-1));

        lua.setTop(0);
        try expectEqual(0, lua.getTop());
    } else {
        var num: i32 = 1;
        while (num <= 10) : (num += 1) {
            lua.pushInteger(num);
        }
        try expectEqual(10, lua.getTop());

        lua.setTop(12);
        try expectEqual(12, lua.getTop());
        try expect(lua.isNil(-1));

        lua.remove(1);
        try expect(lua.isNil(-1));

        lua.insert(1);
        try expect(lua.isNil(1));

        if (ziglua.lang == .lua52) {
            lua.copy(1, 2);
            try expectEqual(3, try lua.toInteger(3));
            try expectEqual(10, try lua.toInteger(-2));
        }

        lua.setTop(0);
        try expectEqual(0, lua.getTop());
    }
}

test "calling a function" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.register("zigadd", ziglua.wrap(add));

    _ = try getGlobal(&lua, "zigadd");
    lua.pushInteger(10);
    lua.pushInteger(32);

    // protectedCall is preferred, but we might as well test call when we know it is safe
    lua.call(2, 1);
    try expectEqual(42, try toInteger(&lua, 1));
}

test "calling a function with cProtectedCall" {
    if (ziglua.lang != .lua51) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var value: i32 = 1234;

    const testFn = struct {
        fn inner(l: *Lua) i32 {
            const passedValue = l.toUserdata(i32, 1) catch unreachable;
            if (passedValue.* != 1234) unreachable;
            return 0;
        }
    }.inner;

    // cProtectedCall doesn't return values on the stack, so the test just makes
    // sure things work!
    try lua.cProtectedCall(ziglua.wrap(testFn), &value);
}

test "version" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    switch (ziglua.lang) {
        .lua52 => try expectEqual(502, lua.version(false).*),
        .lua53 => try expectEqual(503, lua.version(false).*),
        .lua54 => try expectEqual(504, lua.version()),
        else => unreachable,
    }

    lua.checkVersion();
}

test "string buffers" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var buffer: Buffer = undefined;
    buffer.init(lua);

    buffer.addChar('z');
    buffer.addString("igl");

    var str = buffer.prep();
    str[0] = 'u';
    str[1] = 'a';
    buffer.addSize(2);

    buffer.addBytes(" api ");
    lua.pushNumber(5.1);
    buffer.addValue();
    buffer.pushResult();
    try expectEqualStrings("ziglua api 5.1", try lua.toBytes(-1));

    // now test a small buffer
    buffer.init(lua);
    var b = buffer.prep();
    b[0] = 'a';
    b[1] = 'b';
    b[2] = 'c';
    buffer.addSize(3);

    b = buffer.prep();
    @memcpy(b[0..23], "defghijklmnopqrstuvwxyz");
    buffer.addSize(23);
    buffer.pushResult();
    try expectEqualStrings("abcdefghijklmnopqrstuvwxyz", try lua.toBytes(-1));
    lua.pop(1);

    if (ziglua.lang == .lua51) return;

    buffer.init(lua);
    b = buffer.prep();
    @memcpy(b[0..3], "abc");
    buffer.pushResultSize(3);
    try expectEqualStrings("abc", try lua.toBytes(-1));
    lua.pop(1);

    if (ziglua.lang == .luau) return;

    // TODO: maybe implement this for all langs?
    b = buffer.initSize(lua, 20);
    @memcpy(b[0..20], "a" ** 20);
    buffer.pushResultSize(20);

    if (ziglua.lang != .lua54) return;
    try expectEqual(20, buffer.len());
    buffer.sub(10);
    try expectEqual(10, buffer.len());
    try expectEqualStrings("a" ** 10, buffer.addr());

    buffer.addGSub(" append", "append", "appended");
    try expectEqualStrings("a" ** 10 ++ " appended", buffer.addr());
}

test "global table" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // open some libs so we can inspect them
    lua.open(.{ .math = true, .base = true });
    lua.pushGlobalTable();

    if (ziglua.lang == .lua52) {
        // find the print function
        _ = lua.pushString("print");
        lua.getTable(-2);
        try expectEqual(.function, lua.typeOf(-1));

        // index the global table in the global table
        lua.getField(-2, "_G");
        try expectEqual(.table, lua.typeOf(-1));

        // find pi in the math table
        lua.getField(-1, "math");
        try expectEqual(.table, lua.typeOf(-1));
        lua.getField(-1, "pi");
        try expectEqual(.number, lua.typeOf(-1));

        // but the string table should be nil
        lua.pop(2);
        lua.getField(-1, "string");
        try expectEqual(.nil, lua.typeOf(-1));
    } else {
        // find the print function
        _ = lua.pushString("print");
        try expectEqual(.function, lua.getTable(-2));

        // index the global table in the global table
        try expectEqual(.table, lua.getField(-2, "_G"));

        // find pi in the math table
        try expectEqual(.table, lua.getField(-1, "math"));
        try expectEqual(.number, lua.getField(-1, "pi"));

        // but the string table should be nil
        lua.pop(2);
        try expectEqual(.nil, lua.getField(-1, "string"));
    }
}

const sub = struct {
    fn subInner(l: *Lua) i32 {
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a - b);
        return 1;
    }
}.subInner;

test "function registration" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    if (ziglua.lang == .lua51 or ziglua.lang == .luau) {
        // register all functions as part of a table
        const funcs = [_]ziglua.FnReg{
            .{ .name = "add", .func = ziglua.wrap(add) },
        };
        lua.newTable();
        lua.registerFns(null, &funcs);

        _ = lua.getField(-1, "add");
        lua.pushInteger(1);
        lua.pushInteger(2);
        try lua.protectedCall(2, 1, 0);
        try expectEqual(3, lua.toInteger(-1));
        lua.setTop(0);

        // register functions as globals in a library table
        lua.registerFns("testlib", &funcs);

        // testlib.add(1, 2)
        _ = try getGlobal(&lua, "testlib");
        _ = lua.getField(-1, "add");
        lua.pushInteger(1);
        lua.pushInteger(2);
        try lua.protectedCall(2, 1, 0);
        try expectEqual(3, lua.toInteger(-1));

        return;
    }

    // register all functions as part of a table
    const funcs = [_]ziglua.FnReg{
        .{ .name = "add", .func = ziglua.wrap(add) },
        .{ .name = "sub", .func = ziglua.wrap(sub) },
        .{ .name = "placeholder", .func = null },
    };
    lua.newTable();
    lua.setFuncs(&funcs, 0);

    _ = lua.getField(-1, "placeholder");
    try expectEqual(.boolean, lua.typeOf(-1));
    lua.pop(1);
    _ = lua.getField(-1, "add");
    try expectEqual(.function, lua.typeOf(-1));
    lua.pop(1);
    _ = lua.getField(-1, "sub");
    try expectEqual(.function, lua.typeOf(-1));

    // also try calling the sub function sub(42, 40)
    lua.pushInteger(42);
    lua.pushInteger(40);
    try lua.protectedCall(2, 1, 0);
    try expectEqual(2, try lua.toInteger(-1));

    // now test the newlib variation to build a library from functions
    // indirectly tests newLibTable
    lua.newLib(&funcs);
    // add functions to the global table under "funcs"
    lua.setGlobal("funcs");

    try lua.doString("funcs.add(10, 20)");
    try lua.doString("funcs.sub('10', 20)");
    try expectError(error.Runtime, lua.doString("funcs.placeholder()"));
}

test "panic fn" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // just test setting up the panic function
    // it uses longjmp so cannot return here to test
    const panicFn = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            _ = l;
            return 0;
        }
    }.inner);
    try expectEqual(null, lua.atPanic(panicFn));
}

test "warn fn" {
    if (ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.warning("this message is going to the void", false);

    const warnFn = ziglua.wrap(struct {
        fn inner(data: ?*anyopaque, msg: []const u8, to_cont: bool) void {
            _ = data;
            _ = to_cont;
            if (!std.mem.eql(u8, msg, "this will be caught by the warnFn")) std.debug.panic("test failed", .{});
        }
    }.inner);

    lua.setWarnF(warnFn, null);
    lua.warning("this will be caught by the warnFn", false);
}

test "concat" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.pushString("hello ");
    lua.pushNumber(10);
    _ = lua.pushString(" wow!");
    lua.concat(3);

    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        try expectEqualStrings("hello 10.0 wow!", try lua.toBytes(-1));
    } else {
        try expectEqualStrings("hello 10 wow!", try lua.toBytes(-1));
    }
}

test "garbage collector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // because the garbage collector is an opaque, unmanaged
    // thing, it is hard to test, so just run each function
    lua.gcStop();
    lua.gcCollect();
    lua.gcRestart();
    _ = lua.gcCount();
    _ = lua.gcCountB();

    if (ziglua.lang != .lua51) _ = lua.gcIsRunning();
    if (ziglua.lang != .lua54) lua.gcStep();

    if (langIn(.{ .lua51, .lua52, .lua53 })) {
        _ = lua.gcSetPause(2);
        _ = lua.gcSetStepMul(2);
    }

    if (ziglua.lang == .lua52) {
        lua.gcSetGenerational();
        lua.gcSetGenerational();
    } else if (ziglua.lang == .lua54) {
        lua.gcStep(10);
        try expect(lua.gcSetGenerational(0, 10));
        try expect(lua.gcSetIncremental(0, 0, 0));
        try expect(!lua.gcSetIncremental(0, 0, 0));
    } else if (ziglua.lang == .luau) {
        _ = lua.gcSetGoal(10);
        _ = lua.gcSetStepMul(2);
        _ = lua.gcSetStepSize(1);
    }
}

test "extra space" {
    if (ziglua.lang != .lua53 and ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const space: *align(1) usize = @ptrCast(lua.getExtraSpace().ptr);
    space.* = 1024;
    // each new thread is initialized with a copy of the extra space from the main thread
    var thread = lua.newThread();
    try expectEqual(1024, @as(*align(1) usize, @ptrCast(thread.getExtraSpace())).*);
}

test "table access" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("a = { [1] = 'first', key = 'value', ['other one'] = 1234 }");
    _ = try getGlobal(&lua, "a");

    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        try expectEqual(.string, lua.rawGetIndex(1, 1));
        try expectEqualStrings("first", try lua.toBytes(-1));
    }

    try expectEqual(.string, getIndex(&lua, 1, 1));
    try expectEqualStrings("first", try lua.toBytes(-1));

    _ = lua.pushString("key");
    try expectEqual(.string, getTable(&lua, 1));
    try expectEqualStrings("value", try lua.toBytes(-1));

    _ = lua.pushString("other one");
    try expectEqual(.number, rawGetTable(&lua, 1));
    try expectEqual(1234, try toInteger(&lua, -1));

    // a.name = "ziglua"
    _ = lua.pushString("name");
    _ = lua.pushString("ziglua");
    lua.setTable(1);

    // a.lang = "zig"
    _ = lua.pushString("lang");
    _ = lua.pushString("zig");
    lua.rawSetTable(1);

    try expectError(error.Fail, lua.getMetatable(1));

    // create a metatable (it isn't a useful one)
    lua.newTable();

    if (ziglua.lang == .luau)
        lua.pushFunction(ziglua.wrap(add), "add")
    else
        lua.pushFunction(ziglua.wrap(add));
    lua.setField(-2, "__len");
    lua.setMetatable(1);

    try lua.getMetatable(1);
    _ = try lua.getMetaField(1, "__len");
    try expectError(error.Fail, lua.getMetaField(1, "__index"));

    lua.pushBoolean(true);
    lua.setField(1, "bool");

    try lua.doString("b = a.bool");
    try expectEqual(.boolean, try getGlobal(&lua, "b"));
    try expect(lua.toBoolean(-1));

    // create array [1, 2, 3, 4, 5]
    lua.createTable(0, 0);
    var index: i32 = 1;
    while (index <= 5) : (index += 1) {
        lua.pushInteger(index);
        if (ziglua.lang == .lua53 or ziglua.lang == .lua54) lua.setIndex(-2, index) else lua.rawSetIndex(-2, index);
    }

    if (ziglua.lang != .lua51 and ziglua.lang != .luau) {
        try expectEqual(5, lua.rawLen(-1));
        try expectEqual(5, lua.lenRaiseErr(-1));
    }

    // add a few more
    while (index <= 10) : (index += 1) {
        lua.pushInteger(index);
        lua.rawSetIndex(-2, index);
    }
}

test "conversions" {
    if (ziglua.lang != .lua53 and ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // number conversion
    var value: ziglua.Integer = undefined;
    try Lua.numberToInteger(3.14, &value);
    try expectEqual(3, value);
    try expectError(error.Fail, Lua.numberToInteger(@as(ziglua.Number, @floatFromInt(ziglua.max_integer)) + 10, &value));

    // string conversion
    try lua.stringToNumber("1");
    try expect(lua.isInteger(-1));
    try expectEqual(1, try lua.toInteger(1));

    try lua.stringToNumber("  1.0  ");
    try expect(lua.isNumber(-1));
    try expectEqual(1.0, try lua.toNumber(-1));

    try expectError(error.Fail, lua.stringToNumber("a"));
    try expectError(error.Fail, lua.stringToNumber("1.a"));
    try expectError(error.Fail, lua.stringToNumber(""));
}

test "absIndex" {
    if (!langIn(.{ .lua52, .lua53, .lua54 })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.setTop(2);

    try expectEqual(@as(i32, 2), lua.absIndex(-1));
    try expectEqual(@as(i32, 1), lua.absIndex(-2));
}

test "dump and load" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // store a function in a global
    try lua.doString("f = function(x) return function(n) return n + x end end");
    // put the function on the stack
    _ = try getGlobal(&lua, "f");

    const writer = struct {
        fn inner(l: *Lua, buf: []const u8, data: *anyopaque) bool {
            _ = l;
            var arr = ziglua.opaqueCast(std.ArrayList(u8), data);
            arr.appendSlice(buf) catch return false;
            return true;
        }
    }.inner;

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    // save the function as a binary chunk in the buffer
    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        try lua.dump(ziglua.wrap(writer), &buffer, false);
    } else {
        try lua.dump(ziglua.wrap(writer), &buffer);
    }

    // clear the stack
    if (ziglua.lang == .lua54) {
        try lua.closeThread(lua);
    } else lua.setTop(0);

    const reader = struct {
        fn inner(l: *Lua, data: *anyopaque) ?[]const u8 {
            _ = l;
            const arr = ziglua.opaqueCast(std.ArrayList(u8), data);
            return arr.items;
        }
    }.inner;

    // now load the function back onto the stack
    if (ziglua.lang == .lua51) {
        try lua.load(ziglua.wrap(reader), &buffer, "function");
    } else {
        try lua.load(ziglua.wrap(reader), &buffer, "function", .binary);
    }
    try expectEqual(.function, lua.typeOf(-1));

    // run the function (creating a new function)
    lua.pushInteger(5);
    try lua.protectedCall(1, 1, 0);

    // now call the new function (which should return the value + 5)
    lua.pushInteger(6);
    try lua.protectedCall(1, 1, 0);
    try expectEqual(11, try toInteger(&lua, -1));
}

test "threads" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var new_thread = lua.newThread();
    try expectEqual(1, lua.getTop());
    try expectEqual(0, new_thread.getTop());

    lua.pushInteger(10);
    lua.pushNil();

    lua.xMove(new_thread, 2);
    try expectEqual(2, new_thread.getTop());
}

test "userdata and uservalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Data = struct {
        val: i32,
        code: [4]u8,
    };

    // create a Lua-owned pointer to a Data with 2 associated user values
    var data = if (ziglua.lang == .lua54) lua.newUserdata(Data, 2) else lua.newUserdata(Data);
    data.val = 1;
    @memcpy(&data.code, "abcd");

    try expectEqual(data, try lua.toUserdata(Data, 1));
    try expectEqual(@as(*const anyopaque, @ptrCast(data)), try lua.toPointer(1));

    if (ziglua.lang == .lua52 or ziglua.lang == .lua53) {
        // assign the associated user value
        lua.pushNil();
        try lua.setUserValue(1);

        _ = lua.getUserValue(1);
        try expectEqual(.nil, lua.typeOf(-1));
    } else if (ziglua.lang == .lua54) {
        // assign the user values
        lua.pushNumber(1234.56);
        try lua.setIndexUserValue(1, 1);

        _ = lua.pushString("test string");
        try lua.setIndexUserValue(1, 2);

        try expectEqual(.number, try lua.getIndexUserValue(1, 1));
        try expectEqual(1234.56, try lua.toNumber(-1));
        try expectEqual(.string, try lua.getIndexUserValue(1, 2));
        try expectEqualStrings("test string", try lua.toBytes(-1));

        try expectError(error.Fail, lua.setIndexUserValue(1, 3));
        try expectError(error.Fail, lua.getIndexUserValue(1, 3));
    }
}

test "upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // counter from PIL
    const counter = struct {
        fn inner(l: *Lua) i32 {
            var counter = toInteger(l, Lua.upvalueIndex(1)) catch 0;
            counter += 1;
            l.pushInteger(counter);
            l.pushInteger(counter);
            l.replace(Lua.upvalueIndex(1));
            return 1;
        }
    }.inner;

    // Initialize the counter at 0
    lua.pushInteger(0);
    if (ziglua.lang == .luau) lua.pushClosure(ziglua.wrap(counter), "counter", 1) else lua.pushClosure(ziglua.wrap(counter), 1);
    lua.setGlobal("counter");

    // call the function repeatedly, each time ensuring the result increases by one
    var expected: i32 = 1;
    while (expected <= 10) : (expected += 1) {
        _ = try getGlobal(&lua, "counter");
        lua.call(0, 1);
        try expectEqual(expected, try toInteger(&lua, -1));
        lua.pop(1);
    }
}

test "table traversal" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("t = { key = 'value', second = true, third = 1 }");
    _ = try getGlobal(&lua, "t");

    lua.pushNil();

    while (lua.next(1)) {
        switch (lua.typeOf(-1)) {
            .string => {
                try expectEqualStrings("key", try lua.toBytes(-2));
                try expectEqualStrings("value", try lua.toBytes(-1));
            },
            .boolean => {
                try expectEqualStrings("second", try lua.toBytes(-2));
                try expectEqual(true, lua.toBoolean(-1));
            },
            .number => {
                try expectEqualStrings("third", try lua.toBytes(-2));
                try expectEqual(1, try toInteger(&lua, -1));
            },
            else => unreachable,
        }
        lua.pop(1);
    }
}

test "registry" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const key = "mykey";

    // store a string in the registry
    _ = lua.pushString("hello there");
    lua.rawSetPtr(ziglua.registry_index, key);

    // get key from the registry
    _ = lua.rawGetPtr(ziglua.registry_index, key);
    try expectEqualStrings("hello there", try lua.toBytes(-1));
}

test "closing vars" {
    if (ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.open(.{ .base = true });

    // do setup in Lua for ease
    try lua.doString(
        \\closed_vars = 0
        \\mt = { __close = function() closed_vars = closed_vars + 1 end }
    );

    lua.newTable();
    _ = try lua.getGlobal("mt");
    lua.setMetatable(-2);
    lua.toClose(-1);
    lua.closeSlot(-1);
    lua.pop(1);

    lua.newTable();
    _ = try lua.getGlobal("mt");
    lua.setMetatable(-2);
    lua.toClose(-1);
    lua.closeSlot(-1);
    lua.pop(1);

    // this should have incremented "closed_vars" to 2
    _ = try lua.getGlobal("closed_vars");
    try expectEqual(2, try lua.toNumber(-1));
}

test "raise error" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const makeError = struct {
        fn inner(l: *Lua) i32 {
            _ = l.pushString("makeError made an error");
            l.raiseError();
            return 0;
        }
    }.inner;

    if (ziglua.lang == .luau) lua.pushFunction(ziglua.wrap(makeError), "makeError") else lua.pushFunction(ziglua.wrap(makeError));
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
    try expectEqualStrings("makeError made an error", try lua.toBytes(-1));
}

fn continuation(l: *Lua, status: ziglua.Status, ctx: isize) i32 {
    _ = status;

    if (ctx == 5) {
        _ = l.pushString("done");
        return 1;
    } else {
        // yield the current context value
        l.pushInteger(ctx);
        return l.yieldCont(1, ctx + 1, ziglua.wrap(continuation));
    }
}

test "yielding" {
    if (ziglua.lang != .lua53 and ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // here we create some zig functions that will run 5 times, continutally
    // yielding a count until it finally returns the string "done"
    const willYield = struct {
        fn inner(l: *Lua) i32 {
            return continuation(l, .ok, 0);
        }
    }.inner;

    var thread = lua.newThread();
    thread.pushFunction(ziglua.wrap(willYield));

    try expect(!lua.isYieldable());

    var i: i32 = 0;
    if (ziglua.lang == .lua54) {
        try expect(thread.isYieldable());

        var results: i32 = undefined;
        while (i < 5) : (i += 1) {
            try expectEqual(.yield, try thread.resumeThread(lua, 0, &results));
            try expectEqual(i, try thread.toInteger(-1));
            thread.pop(results);
        }

        try expectEqual(.ok, try thread.resumeThread(lua, 0, &results));
    } else {
        try expect(!thread.isYieldable());

        while (i < 5) : (i += 1) {
            try expectEqual(.yield, try thread.resumeThread(lua, 0));
            try expectEqual(i, try thread.toInteger(-1));
            lua.pop(lua.getTop());
        }
        try expectEqual(.ok, try thread.resumeThread(lua, 0));
    }

    try expectEqualStrings("done", try thread.toBytes(-1));
}

fn continuation52(l: *Lua) i32 {
    const ctxOrNull = l.getContext() catch unreachable;
    const ctx = ctxOrNull orelse 0;
    if (ctx == 5) {
        _ = l.pushString("done");
        return 1;
    } else {
        // yield the current context value
        l.pushInteger(ctx);
        return l.yieldCont(1, ctx + 1, ziglua.wrap(continuation52));
    }
}

test "yielding Lua 5.2" {
    if (ziglua.lang != .lua52) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // here we create some zig functions that will run 5 times, continutally
    // yielding a count until it finally returns the string "done"
    const willYield = struct {
        fn inner(l: *Lua) i32 {
            return continuation52(l);
        }
    }.inner;

    var thread = lua.newThread();
    thread.pushFunction(ziglua.wrap(willYield));

    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        try expectEqual(.yield, try thread.resumeThread(lua, 0));
        try expectEqual(i, try thread.toInteger(-1));
        lua.pop(lua.getTop());
    }
    try expectEqual(.ok, try thread.resumeThread(lua, 0));
    try expectEqualStrings("done", try thread.toBytes(-1));
}

test "yielding no continuation" {
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var thread = lua.newThread();
    const func = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.pushInteger(1);
            return l.yield(1);
        }
    }.inner);
    if (ziglua.lang == .luau) {
        thread.pushFunction(func, "yieldfn");
        _ = try thread.resumeThread(null, 0);
    } else {
        thread.pushFunction(func);
        _ = try thread.resumeThread(0);
    }

    try expectEqual(1, thread.toInteger(-1));
}

test "resuming" {
    if (ziglua.lang == .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // here we create a Lua function that will run 5 times, continutally
    // yielding a count until it finally returns the string "done"
    var thread = lua.newThread();
    thread.openLibs();
    try thread.doString(
        \\counter = function()
        \\  coroutine.yield(1)
        \\  coroutine.yield(2)
        \\  coroutine.yield(3)
        \\  coroutine.yield(4)
        \\  coroutine.yield(5)
        \\  return "done"
        \\end
    );
    _ = try getGlobal(&thread, "counter");

    var i: i32 = 1;
    while (i <= 5) : (i += 1) {
        try expectEqual(.yield, if (ziglua.lang == .lua51) try thread.resumeThread(0) else try thread.resumeThread(lua, 0));
        try expectEqual(i, thread.toInteger(-1));
        lua.pop(lua.getTop());
    }
    try expectEqual(.ok, if (ziglua.lang == .lua51) try thread.resumeThread(0) else try thread.resumeThread(lua, 0));
    try expectEqualStrings("done", try thread.toBytes(-1));
}

test "aux check functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.checkAny(1);
            _ = l.checkInteger(2);
            _ = l.checkBytes(3);
            _ = l.checkNumber(4);
            _ = l.checkString(5);
            l.checkType(6, .boolean);
            _ = if (ziglua.lang == .lua52) l.checkUnsigned(7);
            return 0;
        }
    }.inner);

    pushFunction(&lua, function);
    lua.protectedCall(0, 0, 0) catch {
        try expectStringContains("argument #1", try lua.toBytes(-1));
        lua.pop(-1);
    };

    pushFunction(&lua, function);
    lua.pushNil();
    lua.protectedCall(1, 0, 0) catch {
        try expectStringContains("number expected", try lua.toBytes(-1));
        lua.pop(-1);
    };

    pushFunction(&lua, function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.protectedCall(2, 0, 0) catch {
        try expectStringContains("string expected", try lua.toBytes(-1));
        lua.pop(-1);
    };

    pushFunction(&lua, function);
    lua.pushNil();
    lua.pushInteger(3);
    _ = lua.pushBytes("hello world");
    lua.protectedCall(3, 0, 0) catch {
        try expectStringContains("number expected", try lua.toBytes(-1));
        lua.pop(-1);
    };

    pushFunction(&lua, function);
    lua.pushNil();
    lua.pushInteger(3);
    _ = lua.pushBytes("hello world");
    lua.pushNumber(4);
    lua.protectedCall(4, 0, 0) catch {
        try expectStringContains("string expected", try lua.toBytes(-1));
        lua.pop(-1);
    };

    pushFunction(&lua, function);
    lua.pushNil();
    lua.pushInteger(3);
    _ = lua.pushBytes("hello world");
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.protectedCall(5, 0, 0) catch {
        try expectStringContains("boolean expected", try lua.toBytes(-1));
        lua.pop(-1);
    };

    if (ziglua.lang == .lua52) {
        lua.pushFunction(function);
        lua.pushNil();
        lua.pushInteger(3);
        _ = lua.pushBytes("hello world");
        lua.pushNumber(4);
        _ = lua.pushString("hello world");
        lua.pushBoolean(true);
        lua.protectedCall(6, 0, 0) catch {
            try expectEqualStrings("bad argument #7 to '?' (number expected, got no value)", try lua.toBytes(-1));
            lua.pop(-1);
        };
    }

    pushFunction(&lua, function);
    // test pushFail here (currently acts the same as pushNil)
    if (ziglua.lang == .lua54) lua.pushFail() else lua.pushNil();
    lua.pushInteger(3);
    _ = lua.pushBytes("hello world");
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.pushBoolean(true);
    if (ziglua.lang == .lua52) {
        lua.pushUnsigned(1);
        try lua.protectedCall(7, 0, 0);
    } else try lua.protectedCall(6, 0, 0);
}

test "aux opt functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            expectEqual(10, l.optInteger(1, 10)) catch unreachable;
            expectEqualStrings("zig", l.optBytes(2, "zig")) catch unreachable;
            expectEqual(1.23, l.optNumber(3, 1.23)) catch unreachable;
            expectEqualStrings("lang", std.mem.span(l.optString(4, "lang"))) catch unreachable;
            return 0;
        }
    }.inner);

    pushFunction(&lua, function);
    try lua.protectedCall(0, 0, 0);

    pushFunction(&lua, function);
    lua.pushInteger(10);
    _ = lua.pushBytes("zig");
    lua.pushNumber(1.23);
    _ = lua.pushString("lang");
    try lua.protectedCall(4, 0, 0);
}

test "checkOption" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Variant = enum {
        one,
        two,
        three,
    };

    const function = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            const option = l.checkOption(Variant, 1, .one);
            l.pushInteger(switch (option) {
                .one => 1,
                .two => 2,
                .three => 3,
            });
            return 1;
        }
    }.inner);

    pushFunction(&lua, function);
    _ = lua.pushString("one");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(1, try toInteger(&lua, -1));
    lua.pop(1);

    pushFunction(&lua, function);
    _ = lua.pushString("two");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(2, try toInteger(&lua, -1));
    lua.pop(1);

    pushFunction(&lua, function);
    _ = lua.pushString("three");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(3, try toInteger(&lua, -1));
    lua.pop(1);

    // try the default now
    pushFunction(&lua, function);
    try lua.protectedCall(0, 1, 0);
    try expectEqual(1, try toInteger(&lua, -1));
    lua.pop(1);

    // check the raised error
    pushFunction(&lua, function);
    _ = lua.pushString("unknown");
    try expectError(error.Runtime, lua.protectedCall(1, 1, 0));
    try expectStringContains("(invalid option 'unknown')", try lua.toBytes(-1));
}

test "get global fail" {
    if (ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectError(error.Fail, lua.getGlobal("foo"));
}

test "globalSub" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.globalSub("-gity -!", "-", "zig");
    try expectEqualStrings("ziggity zig!", try lua.toBytes(-1));
}

test "loadBuffer" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    if (ziglua.lang == .lua51) {
        _ = try lua.loadBuffer("global = 10", "chunkname");
    } else _ = try lua.loadBuffer("global = 10", "chunkname", .text);

    try lua.protectedCall(0, ziglua.mult_return, 0);
    _ = try getGlobal(&lua, "global");
    try expectEqual(10, try toInteger(&lua, -1));
}

test "where" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const whereFn = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.where(1);
            return 1;
        }
    }.inner);

    pushFunction(&lua, whereFn);
    lua.setGlobal("whereFn");

    try lua.doString(
        \\
        \\ret = whereFn()
    );

    _ = try getGlobal(&lua, "ret");
    try expectEqualStrings("[string \"...\"]:2: ", try lua.toBytes(-1));
}

test "ref" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.Fail, lua.ref(ziglua.registry_index));
    try expectEqual(0, lua.getTop());

    _ = lua.pushBytes("Hello there");
    const ref = try lua.ref(ziglua.registry_index);

    _ = lua.rawGetIndex(ziglua.registry_index, ref);
    try expectEqualStrings("Hello there", try lua.toBytes(-1));

    lua.unref(ziglua.registry_index, ref);
}

test "ref luau" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.Fail, lua.ref(1));
    try expectEqual(1, lua.getTop());

    // In luau lua.ref does not pop the item from the stack
    // and the data is stored in the registry_index by default
    lua.pushBytes("Hello there");
    const ref = try lua.ref(2);

    _ = lua.rawGetIndex(ziglua.registry_index, ref);
    try expectEqualStrings("Hello there", try lua.toBytes(-1));

    lua.unref(ref);
}

test "metatables" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("f = function() return 10 end");

    try lua.newMetatable("mt");

    if (ziglua.lang != .lua51 and ziglua.lang != .luau) {
        _ = lua.getMetatableRegistry("mt");
        try expect(lua.compare(1, 2, .eq));
        lua.pop(1);
    }

    // set the len metamethod to the function f
    _ = try getGlobal(&lua, "f");
    lua.setField(1, "__len");

    lua.newTable();
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) {
        lua.setMetatableRegistry("mt");
    } else {
        _ = lua.getField(ziglua.registry_index, "mt");
        lua.setMetatable(-2);
    }

    try lua.callMeta(-1, "__len");
    try expectEqual(10, try toNumber(&lua, -1));
}

test "args and errors" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const argCheck = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.argCheck(false, 1, "error!");
            return 0;
        }
    }.inner);

    pushFunction(&lua, argCheck);
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));

    const raisesError = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.raiseErrorStr("some error %s!", .{"zig"});
            unreachable;
        }
    }.inner);

    pushFunction(&lua, raisesError);
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
    try expectEqualStrings("some error zig!", try lua.toBytes(-1));

    if (ziglua.lang != .lua54) return;

    const argExpected = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.argExpected(true, 1, "string");
            return 0;
        }
    }.inner);

    lua.pushFunction(argExpected);
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
}

test "traceback" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const tracebackFn = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.traceback(l, "", 1);
            return 1;
        }
    }.inner);

    lua.pushFunction(tracebackFn);
    lua.setGlobal("tracebackFn");
    try lua.doString("res = tracebackFn()");

    _ = try getGlobal(&lua, "res");
    try expectEqualStrings("\nstack traceback:\n\t[string \"res = tracebackFn()\"]:1: in main chunk", try lua.toBytes(-1));
}

test "getSubtable" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\a = {
        \\  b = {},
        \\}
    );
    _ = try getGlobal(&lua, "a");

    // get the subtable a.b
    try lua.getSubtable(-1, "b");

    // fail to get the subtable a.c (but it is created)
    try expectError(error.Fail, lua.getSubtable(-2, "c"));

    // now a.c will pass
    try lua.getSubtable(-3, "b");
}

test "userdata" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Type = struct { a: i32, b: f32 };
    try lua.newMetatable("Type");

    const checkUdata = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            const ptr = l.checkUserdata(Type, 1, "Type");
            if (ptr.a != 1234) {
                _ = l.pushBytes("error!");
                l.raiseError();
            }
            if (ptr.b != 3.14) {
                _ = l.pushBytes("error!");
                l.raiseError();
            }
            return 1;
        }
    }.inner);

    pushFunction(&lua, checkUdata);

    {
        var t = if (ziglua.lang == .lua54) lua.newUserdata(Type, 0) else lua.newUserdata(Type);
        if (ziglua.lang == .lua51 or ziglua.lang == .luau) {
            _ = lua.getField(ziglua.registry_index, "Type");
            lua.setMetatable(-2);
        } else lua.setMetatableRegistry("Type");

        t.a = 1234;
        t.b = 3.14;

        // call checkUdata asserting that the udata passed in with the
        // correct metatable and values
        try lua.protectedCall(1, 1, 0);
    }

    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    const testUdata = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            const ptr = l.testUserdata(Type, 1, "Type") catch {
                _ = l.pushBytes("error!");
                l.raiseError();
            };
            if (ptr.a != 1234) {
                _ = l.pushBytes("error!");
                l.raiseError();
            }
            if (ptr.b != 3.14) {
                _ = l.pushBytes("error!");
                l.raiseError();
            }
            return 0;
        }
    }.inner);

    lua.pushFunction(testUdata);

    {
        var t = if (ziglua.lang == .lua54) lua.newUserdata(Type, 0) else lua.newUserdata(Type);
        lua.setMetatableRegistry("Type");
        t.a = 1234;
        t.b = 3.14;

        // call checkUdata asserting that the udata passed in with the
        // correct metatable and values
        try lua.protectedCall(1, 0, 0);
    }
}

test "userdata slices" {
    const Integer = ziglua.Integer;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.newMetatable("FixedArray");

    // create an array of 10
    const slice = if (ziglua.lang == .lua54) lua.newUserdataSlice(Integer, 10, 0) else lua.newUserdataSlice(Integer, 10);
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) {
        _ = lua.getField(ziglua.registry_index, "FixedArray");
        lua.setMetatable(-2);
    } else lua.setMetatableRegistry("FixedArray");

    for (slice, 1..) |*item, index| {
        item.* = @intCast(index);
    }

    const udataFn = struct {
        fn inner(l: *Lua) i32 {
            _ = l.checkUserdataSlice(Integer, 1, "FixedArray");

            if (ziglua.lang != .lua51 and ziglua.lang != .luau) _ = l.testUserdataSlice(Integer, 1, "FixedArray") catch unreachable;

            const arr = l.toUserdataSlice(Integer, 1) catch unreachable;
            for (arr, 1..) |item, index| {
                if (item != index) l.raiseErrorStr("something broke!", .{});
            }

            return 0;
        }
    }.inner;

    pushFunction(&lua, ziglua.wrap(udataFn));
    lua.pushValue(2);

    try lua.protectedCall(1, 0, 0);
}

test "function environments" {
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("function test() return x end");

    // set the global _G.x to be 10
    lua.pushInteger(10);
    lua.setGlobal("x");

    _ = try getGlobal(&lua, "test");
    try lua.protectedCall(0, 1, 0);
    try testing.expectEqual(10, lua.toInteger(1));
    lua.pop(1);

    // now set the functions table to have a different value of x
    _ = try getGlobal(&lua, "test");
    lua.newTable();
    lua.pushInteger(20);
    lua.setField(2, "x");
    try lua.setFnEnvironment(1);

    try lua.protectedCall(0, 1, 0);
    try testing.expectEqual(20, lua.toInteger(1));
    lua.pop(1);

    _ = try getGlobal(&lua, "test");
    lua.getFnEnvironment(1);
    _ = lua.getField(2, "x");
    try testing.expectEqual(20, lua.toInteger(3));
}

test "objectLen" {
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushString("lua");
    try testing.expectEqual(3, lua.objectLen(-1));
}

// Debug Library

test "debug interface" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  local y = x * 2
        \\  y = y + 2
        \\  return x + y
        \\end
    );
    _ = try getGlobal(&lua, "f");

    var info: DebugInfo = undefined;
    lua.getInfo(.{
        .@">" = true,
        .l = true,
        .S = true,
        .n = true,
        .u = true,
        .t = true,
    }, &info);

    // get information about the function
    try expectEqual(.lua, info.what);
    try expectEqual(.other, info.name_what);
    const len = std.mem.len(@as([*:0]u8, @ptrCast(&info.short_src)));
    try expectEqualStrings("[string \"f = function(x)...\"]", info.short_src[0..len]);
    try expectEqual(1, info.first_line_defined);
    try expectEqual(5, info.last_line_defined);
    try expectEqual(1, info.num_params);
    try expectEqual(0, info.num_upvalues);
    try expect(!info.is_tail_call);
    try expectEqual(null, info.current_line);

    // create a hook
    const hook = struct {
        fn inner(l: *Lua, event: ziglua.Event, i: *DebugInfo) void {
            switch (event) {
                .call => {
                    if (ziglua.lang == .lua54) l.getInfo(.{ .l = true, .r = true }, i) else l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 2) std.debug.panic("Expected line to be 2", .{});
                    _ = if (ziglua.lang == .lua54) l.getLocal(i, i.first_transfer) catch unreachable else l.getLocal(i, 1) catch unreachable;
                    if ((l.toNumber(-1) catch unreachable) != 3) std.debug.panic("Expected x to equal 3", .{});
                },
                .line => if (i.current_line.? == 4) {
                    // modify the value of y to be 0 right before returning
                    l.pushNumber(0);
                    _ = l.setLocal(i, 2) catch unreachable;
                },
                .ret => {
                    if (ziglua.lang == .lua54) l.getInfo(.{ .l = true, .r = true }, i) else l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 4) std.debug.panic("Expected line to be 4", .{});
                    _ = if (ziglua.lang == .lua54) l.getLocal(i, i.first_transfer) catch unreachable else l.getLocal(i, 1) catch unreachable;
                    if ((l.toNumber(-1) catch unreachable) != 3) std.debug.panic("Expected result to equal 3", .{});
                },
                else => unreachable,
            }
        }
    }.inner;

    // run the hook when a function is called
    try expectEqual(null, lua.getHook());
    try expectEqual(ziglua.HookMask{}, lua.getHookMask());
    try expectEqual(0, lua.getHookCount());

    lua.setHook(ziglua.wrap(hook), .{ .call = true, .line = true, .ret = true }, 0);
    try expectEqual(ziglua.wrap(hook), lua.getHook());
    try expectEqual(ziglua.HookMask{ .call = true, .line = true, .ret = true }, lua.getHookMask());

    _ = try getGlobal(&lua, "f");
    lua.pushNumber(3);
    try lua.protectedCall(1, 1, 0);
}

test "debug interface Lua 5.1 and Luau" {
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  local y = x * 2
        \\  y = y + 2
        \\  return x + y
        \\end
    );
    _ = try getGlobal(&lua, "f");

    var info: DebugInfo = undefined;

    if (ziglua.lang == .lua51) {
        lua.getInfo(.{
            .@">" = true,
            .l = true,
            .S = true,
            .n = true,
            .u = true,
        }, &info);
    } else {
        lua.getInfo(-1, .{
            .l = true,
            .s = true,
            .n = true,
            .u = true,
        }, &info);
    }

    // get information about the function
    try expectEqual(.lua, info.what);
    const len = std.mem.len(@as([*:0]u8, @ptrCast(&info.short_src)));
    try expectEqual(1, info.first_line_defined);

    if (ziglua.lang == .luau) {
        try expectEqual(1, info.current_line);
        try expectEqualStrings("[string \"...\"]", info.short_src[0..len]);
        return;
    }

    try expectEqual(null, info.current_line);
    try expectEqualStrings("[string \"f = function(x)...\"]", info.short_src[0..len]);
    try expectEqual(.other, info.name_what);
    try expectEqual(5, info.last_line_defined);

    // create a hook
    const hook = struct {
        fn inner(l: *Lua, event: ziglua.Event, i: *DebugInfo) void {
            switch (event) {
                .call => {
                    l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 2) std.debug.panic("Expected line to be 2", .{});
                    _ = l.getLocal(i, 1) catch unreachable;
                    if ((l.toNumber(-1)) != 3) std.debug.panic("Expected x to equal 3", .{});
                },
                .line => if (i.current_line.? == 4) {
                    // modify the value of y to be 0 right before returning
                    l.pushNumber(0);
                    _ = l.setLocal(i, 2) catch unreachable;
                },
                .ret => {
                    l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 4) std.debug.panic("Expected line to be 4", .{});
                    _ = l.getLocal(i, 1) catch unreachable;
                    if ((l.toNumber(-1)) != 3) std.debug.panic("Expected result to equal 3", .{});
                },
                else => unreachable,
            }
        }
    }.inner;

    // run the hook when a function is called
    try expectEqual(@as(?ziglua.CHookFn, null), lua.getHook());
    try expectEqual(ziglua.HookMask{}, lua.getHookMask());
    try expectEqual(@as(i32, 0), lua.getHookCount());

    lua.setHook(ziglua.wrap(hook), .{ .call = true, .line = true, .ret = true }, 0);
    try expectEqual(@as(?ziglua.CHookFn, ziglua.wrap(hook)), lua.getHook());
    try expectEqual(ziglua.HookMask{ .call = true, .line = true, .ret = true }, lua.getHookMask());

    lua.getGlobal("f");
    lua.pushNumber(3);
    try lua.protectedCall(1, 1, 0);
}

test "debug upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  return function(y)
        \\    return x + y
        \\  end
        \\end
        \\addone = f(1)
    );
    _ = try getGlobal(&lua, "addone");

    // index doesn't exist
    try expectError(error.Fail, lua.getUpvalue(1, 2));

    // inspect the upvalue (should be x)
    try expectEqualStrings(if (ziglua.lang == .luau) "" else "x", try lua.getUpvalue(-1, 1));
    try expectEqual(1, try toNumber(&lua, -1));
    lua.pop(1);

    // now make the function an "add five" function
    lua.pushNumber(5);
    _ = try lua.setUpvalue(-2, 1);

    // test a bad index (the valid one's result is unpredicable)
    if (ziglua.lang == .lua54) try expectError(error.Fail, lua.upvalueId(-1, 2));

    // call the new function (should return 7)
    lua.pushNumber(2);
    try lua.protectedCall(1, 1, 0);
    try expectEqual(7, try toNumber(&lua, -1));

    if (ziglua.lang == .lua51 or ziglua.lang == .luau) return;

    lua.pop(1);

    try lua.doString(
        \\addthree = f(3)
    );

    _ = try getGlobal(&lua, "addone");
    _ = try getGlobal(&lua, "addthree");

    // now addone and addthree share the same upvalue
    lua.upvalueJoin(-2, 1, -1, 1);
    try expect((try lua.upvalueId(-2, 1)) == try lua.upvalueId(-1, 1));
}

test "getstack" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectError(error.Fail, lua.getStack(1));

    const function = struct {
        fn inner(l: *Lua) i32 {
            // get info about calling lua function
            var info = l.getStack(1) catch unreachable;
            l.getInfo(.{ .n = true }, &info);
            expectEqualStrings("g", info.name.?) catch unreachable;
            return 0;
        }
    }.inner;

    lua.pushFunction(ziglua.wrap(function));
    lua.setGlobal("f");

    try lua.doString(
        \\g = function()
        \\  f()
        \\end
        \\g()
    );
}

test "compile and run bytecode" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    // Load bytecode
    const src = "return 133";
    const bc = try ziglua.compile(testing.allocator, src, ziglua.CompileOptions{});
    defer testing.allocator.free(bc);

    try lua.loadBytecode("...", bc);
    try lua.protectedCall(0, 1, 0);
    const v = try lua.toInteger(-1);
    try expectEqual(133, v);

    // Try mutable globals.  Calls to mutable globals should produce longer bytecode.
    const src2 = "Foo.print()\nBar.print()";
    const bc1 = try ziglua.compile(testing.allocator, src2, ziglua.CompileOptions{});
    defer testing.allocator.free(bc1);

    const options = ziglua.CompileOptions{
        .mutable_globals = &[_:null]?[*:0]const u8{ "Foo", "Bar" },
    };
    const bc2 = try ziglua.compile(testing.allocator, src2, options);
    defer testing.allocator.free(bc2);
    // A really crude check for changed bytecode.  Better would be to match
    // produced bytecode in text format, but the API doesn't support it.
    try expect(bc1.len < bc2.len);
}

test "userdata dtor" {
    if (ziglua.lang != .luau) return;
    var gc_hits: i32 = 0;

    const Data = struct {
        gc_hits_ptr: *i32,

        pub fn dtor(udata: *anyopaque) void {
            const self: *@This() = @alignCast(@ptrCast(udata));
            self.gc_hits_ptr.* = self.gc_hits_ptr.* + 1;
        }
    };

    // create a Lua-owned pointer to a Data, configure Data with a destructor.
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit(); // forces dtors to be called at the latest

        var data = lua.newUserdataDtor(Data, ziglua.wrap(Data.dtor));
        data.gc_hits_ptr = &gc_hits;
        try expectEqual(@as(*anyopaque, @ptrCast(data)), try lua.toPointer(1));
        try expectEqual(0, gc_hits);
        lua.pop(1); // don't let the stack hold a ref to the user data
        lua.gcCollect();
        try expectEqual(1, gc_hits);
        lua.gcCollect();
        try expectEqual(1, gc_hits);
    }
}

test "tagged userdata" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit(); // forces dtors to be called at the latest

    const Data = struct {
        val: i32,
    };

    // create a Lua-owned tagged pointer
    var data = lua.newUserdataTagged(Data, 13);
    data.val = 1;

    const data2 = try lua.toUserdataTagged(Data, -1, 13);
    try testing.expectEqual(data.val, data2.val);

    var tag = try lua.userdataTag(-1);
    try testing.expectEqual(13, tag);

    lua.setUserdataTag(-1, 100);
    tag = try lua.userdataTag(-1);
    try testing.expectEqual(100, tag);

    // Test that tag mismatch error handling works.  Userdata is not tagged with 123.
    try expectError(error.Fail, lua.toUserdataTagged(Data, -1, 123));

    // should not fail
    _ = try lua.toUserdataTagged(Data, -1, 100);

    // Integer is not userdata, so userdataTag should fail.
    lua.pushInteger(13);
    try expectError(error.Fail, lua.userdataTag(-1));
}

fn vectorCtor(l: *Lua) i32 {
    const x = l.toNumber(1) catch unreachable;
    const y = l.toNumber(2) catch unreachable;
    const z = l.toNumber(3) catch unreachable;
    if (ziglua.luau_vector_size == 4) {
        const w = l.optNumber(4, 0);
        l.pushVector(@floatCast(x), @floatCast(y), @floatCast(z), @floatCast(w));
    } else {
        l.pushVector(@floatCast(x), @floatCast(y), @floatCast(z));
    }
    return 1;
}

test "luau vectors" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();
    lua.register("vector", ziglua.wrap(vectorCtor));

    try lua.doString(
        \\function test()
        \\  local a = vector(1, 2, 3)
        \\  local b = vector(4, 5, 6)
        \\  local c = (a + b) * vector(2, 2, 2)
        \\  return vector(c.x, c.y, c.z)
        \\end
    );
    _ = try lua.getGlobal("test");
    try lua.protectedCall(0, 1, 0);
    var v = try lua.toVector(-1);
    try testing.expectEqualSlices(f32, &[3]f32{ 10, 14, 18 }, v[0..3]);

    if (ziglua.luau_vector_size == 3) lua.pushVector(1, 2, 3) else lua.pushVector(1, 2, 3, 4);
    try expect(lua.isVector(-1));
    v = try lua.toVector(-1);
    const expected = if (ziglua.luau_vector_size == 3) [3]f32{ 1, 2, 3 } else [4]f32{ 1, 2, 3, 4 };
    try expectEqual(expected, v);
    try expectEqualStrings("vector", lua.typeNameIndex(-1));

    lua.pushInteger(5);
    try expect(!lua.isVector(-1));
}

test "luau 4-vectors" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();
    lua.register("vector", ziglua.wrap(vectorCtor));

    // More specific 4-vector tests
    if (ziglua.luau_vector_size == 4) {
        try lua.doString(
            \\local a = vector(1, 2, 3, 4)
            \\local b = vector(5, 6, 7, 8)
            \\return a + b
        );
        const vec4 = try lua.toVector(-1);
        try expectEqual([4]f32{ 6, 8, 10, 12 }, vec4);
    }
}
