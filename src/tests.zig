const std = @import("std");
const testing = std.testing;

const ziglua = @import("ziglua");

const Buffer = ziglua.Buffer;
const DebugInfo = ziglua.DebugInfo;
const Lua = ziglua.Lua;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

fn expectStringContains(actual: []const u8, expected_contains: []const u8) !void {
    if (std.mem.indexOf(u8, actual, expected_contains) == null) return;
    return error.LuaTestExpectedStringContains;
}

/// Return true if ziglua.lang matches any of the given langs
inline fn langIn(langs: anytype) bool {
    inline for (langs) |lang| if (ziglua.lang == lang) return true;
    return false;
}

test "initialization" {
    // initialize the Zig wrapper
    var lua = try Lua.init(testing.allocator);
    try expectEqual(ziglua.Status.ok, lua.status());
    lua.deinit();

    // attempt to initialize the Zig wrapper with no memory
    try expectError(error.OutOfMemory, Lua.init(testing.failing_allocator));
}

test "Zig allocator access" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const inner = struct {
        fn inner(l: *Lua) !i32 {
            const allocator = l.allocator();

            const num = try l.toInteger(1);

            // Use the allocator
            const nums = try allocator.alloc(i32, @intCast(num));
            defer allocator.free(nums);

            // Do something pointless to use the slice
            var sum: i32 = 0;
            for (nums, 0..) |*n, i| n.* = @intCast(i);
            for (nums) |n| sum += n;

            l.pushInteger(sum);
            return 1;
        }
    }.inner;

    lua.pushFunction(ziglua.wrap(inner));
    lua.pushInteger(10);
    try lua.protectedCall(.{ .args = 1, .results = 1 });

    try expectEqual(45, try lua.toInteger(-1));
}

test "standard library loading" {
    // open all standard libraries
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.openLibs();
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

        if (ziglua.lang != .lua51 and ziglua.lang != .lua53 and ziglua.lang != .lua54) lua.openBit32();

        if (ziglua.lang != .luau) {
            lua.openPackage();
            lua.openIO();
        }
        if (ziglua.lang != .lua51 and ziglua.lang != .luajit) lua.openCoroutine();
        if (ziglua.lang != .lua51 and ziglua.lang != .lua52 and ziglua.lang != .luajit) lua.openUtf8();
    }
}

test "number conversion success and failure" {
    const lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.pushString("1234.5678");
    try expectEqual(1234.5678, try lua.toNumber(-1));

    _ = lua.pushString("1234");
    try expectEqual(1234, try lua.toInteger(-1));

    lua.pushNil();
    try expectError(error.LuaError, lua.toNumber(-1));
    try expectError(error.LuaError, lua.toInteger(-1));

    _ = lua.pushString("fail");
    try expectError(error.LuaError, lua.toNumber(-1));
    try expectError(error.LuaError, lua.toInteger(-1));
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
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
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
    try expectEqual(1, try lua.toInteger(-1));
    try expectEqualStrings("number", lua.typeNameIndex(-1));

    var value: i32 = 0;
    lua.pushLightUserdata(&value);
    try expectEqual(.light_userdata, lua.typeOf(-1));
    try expect(lua.isLightUserdata(-1));
    try expect(lua.isUserdata(-1));

    lua.pushNumber(0.1);
    try expectEqual(.number, lua.typeOf(-1));
    try expect(lua.isNumber(-1));
    try expectEqual(0.1, try lua.toNumber(-1));

    _ = lua.pushThread();
    try expectEqual(.thread, lua.typeOf(-1));
    try expect(lua.isThread(-1));
    try expectEqual(lua, (try lua.toThread(-1)));

    try expectEqualStrings("all your codebase are belong to us", lua.pushStringZ("all your codebase are belong to us"));
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    lua.pushFunction(ziglua.wrap(add));
    try expectEqual(.function, lua.typeOf(-1));
    try expect(lua.isCFunction(-1));
    try expect(lua.isFunction(-1));
    try expectEqual(ziglua.wrap(add), try lua.toCFunction(-1));

    try expectEqualStrings("hello world", lua.pushString("hello world"));
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));

    _ = lua.pushFString("%s %s %d", .{ "hello", "world", @as(i32, 10) });
    try expectEqual(.string, lua.typeOf(-1));
    try expect(lua.isString(-1));
    try expectEqualStrings("hello world 10", try lua.toString(-1));

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

    _ = lua.pushString("hello");
    try expectError(error.LuaError, lua.toUnsigned(-1));
}

test "executing string contents" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    try lua.loadString("f = function(x) return x + 10 end");
    try lua.protectedCall(.{});
    try lua.loadString("a = f(2)");
    try lua.protectedCall(.{});

    try expectEqual(.number, try lua.getGlobal("a"));
    try expectEqual(12, try lua.toInteger(1));

    try expectError(if (ziglua.lang == .luau) error.LuaError else error.LuaSyntax, lua.loadString("bad syntax"));
    try lua.loadString("a = g()");
    try expectError(error.LuaRuntime, lua.protectedCall(.{}));
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
    try expectError(error.LuaError, lua.checkStack(1_000_000));

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

    _ = try lua.getGlobal("zigadd");
    lua.pushInteger(10);
    lua.pushInteger(32);

    // protectedCall is preferred, but we might as well test call when we know it is safe
    lua.call(.{ .args = 2, .results = 1 });
    try expectEqual(42, try lua.toInteger(1));
}

test "calling a function with cProtectedCall" {
    if (ziglua.lang != .lua51) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var value: i32 = 1234;

    const testFn = struct {
        fn inner(l: *Lua) !i32 {
            const passedValue = try l.toUserdata(i32, 1);
            if (passedValue.* != 1234) unreachable;
            return 0;
        }
    }.inner;

    // cProtectedCall doesn't return values on the stack, so the test just makes
    // sure things work!
    try lua.cProtectedCall(ziglua.wrap(testFn), &value);
}

test "version" {
    if (ziglua.lang == .lua51 or ziglua.lang == .luau or ziglua.lang == .luajit) return;

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
    buffer.addStringZ("igl");

    var str = buffer.prep();
    str[0] = 'u';
    str[1] = 'a';
    buffer.addSize(2);

    buffer.addString(" api ");
    lua.pushNumber(5.1);
    buffer.addValue();
    buffer.pushResult();
    try expectEqualStrings("ziglua api 5.1", try lua.toString(-1));

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
    try expectEqualStrings("abcdefghijklmnopqrstuvwxyz", try lua.toString(-1));
    lua.pop(1);

    if (ziglua.lang == .lua51 or ziglua.lang == .luajit) return;

    buffer.init(lua);
    b = buffer.prep();
    @memcpy(b[0..3], "abc");
    buffer.pushResultSize(3);
    try expectEqualStrings("abc", try lua.toString(-1));
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
    if (langIn(.{ .lua51, .luajit, .luau })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // open some libs so we can inspect them
    lua.openBase();
    lua.openMath();
    lua.pushGlobalTable();

    // find the print function
    _ = lua.pushStringZ("print");
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

    if (langIn(.{ .lua51, .luajit, .luau })) {
        // register all functions as part of a table
        const funcs = [_]ziglua.FnReg{
            .{ .name = "add", .func = ziglua.wrap(add) },
        };
        lua.newTable();
        lua.registerFns(null, &funcs);

        _ = lua.getField(-1, "add");
        lua.pushInteger(1);
        lua.pushInteger(2);
        try lua.protectedCall(.{ .args = 2, .results = 1 });
        try expectEqual(3, lua.toInteger(-1));
        lua.setTop(0);

        // register functions as globals in a library table
        lua.registerFns("testlib", &funcs);

        // testlib.add(1, 2)
        _ = try lua.getGlobal("testlib");
        _ = lua.getField(-1, "add");
        lua.pushInteger(1);
        lua.pushInteger(2);
        try lua.protectedCall(.{ .args = 2, .results = 1 });
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
    try lua.protectedCall(.{ .args = 2, .results = 1 });
    try expectEqual(2, try lua.toInteger(-1));

    // now test the newlib variation to build a library from functions
    // indirectly tests newLibTable
    lua.newLib(&funcs);
    // add functions to the global table under "funcs"
    lua.setGlobal("funcs");

    try lua.doString("funcs.add(10, 20)");
    try lua.doString("funcs.sub('10', 20)");
    try expectError(error.LuaRuntime, lua.doString("funcs.placeholder()"));
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

    _ = lua.pushStringZ("hello ");
    lua.pushNumber(10);
    _ = lua.pushStringZ(" wow!");
    lua.concat(3);

    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        try expectEqualStrings("hello 10.0 wow!", try lua.toString(-1));
    } else {
        try expectEqualStrings("hello 10 wow!", try lua.toString(-1));
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
    lua.gcStep(10);

    if (ziglua.lang != .lua51 and ziglua.lang != .luajit) _ = lua.gcIsRunning();

    if (langIn(.{ .lua51, .lua52, .lua53 })) {
        _ = lua.gcSetPause(2);
        _ = lua.gcSetStepMul(2);
    }

    if (ziglua.lang == .lua52) {
        lua.gcSetGenerational();
        lua.gcSetGenerational();
    } else if (ziglua.lang == .lua54) {
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
    _ = try lua.getGlobal("a");

    if (ziglua.lang == .lua53 or ziglua.lang == .lua54) {
        try expectEqual(.string, lua.rawGetIndex(1, 1));
        try expectEqualStrings("first", try lua.toString(-1));
    }

    try expectEqual(.string, switch (ziglua.lang) {
        .lua53, .lua54 => lua.getIndex(1, 1),
        else => lua.rawGetIndex(1, 1),
    });
    try expectEqualStrings("first", try lua.toString(-1));

    _ = lua.pushStringZ("key");
    try expectEqual(.string, lua.getTable(1));
    try expectEqualStrings("value", try lua.toString(-1));

    _ = lua.pushStringZ("other one");
    try expectEqual(.number, lua.rawGetTable(1));
    try expectEqual(1234, try lua.toInteger(-1));

    // a.name = "ziglua"
    _ = lua.pushStringZ("name");
    _ = lua.pushStringZ("ziglua");
    lua.setTable(1);

    // a.lang = "zig"
    _ = lua.pushStringZ("lang");
    _ = lua.pushStringZ("zig");
    lua.rawSetTable(1);

    try expectError(error.LuaError, lua.getMetatable(1));

    // create a metatable (it isn't a useful one)
    lua.newTable();

    lua.pushFunction(ziglua.wrap(add));
    lua.setField(-2, "__len");
    lua.setMetatable(1);

    try lua.getMetatable(1);
    _ = try lua.getMetaField(1, "__len");
    try expectError(error.LuaError, lua.getMetaField(1, "__index"));

    lua.pushBoolean(true);
    lua.setField(1, "bool");

    try lua.doString("b = a.bool");
    try expectEqual(.boolean, try lua.getGlobal("b"));
    try expect(lua.toBoolean(-1));

    // create array [1, 2, 3, 4, 5]
    lua.createTable(0, 0);
    var index: i32 = 1;
    while (index <= 5) : (index += 1) {
        lua.pushInteger(index);
        if (ziglua.lang == .lua53 or ziglua.lang == .lua54) lua.setIndex(-2, index) else lua.rawSetIndex(-2, index);
    }

    if (!langIn(.{ .lua51, .luajit, .luau })) {
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
    try expectEqual(3, Lua.numberToInteger(3.14));
    try expectError(error.LuaError, Lua.numberToInteger(@as(ziglua.Number, @floatFromInt(ziglua.max_integer)) + 10));

    // string conversion
    try lua.stringToNumber("1");
    try expect(lua.isInteger(-1));
    try expectEqual(1, try lua.toInteger(1));

    try lua.stringToNumber("  1.0  ");
    try expect(lua.isNumber(-1));
    try expectEqual(1.0, try lua.toNumber(-1));

    try expectError(error.LuaError, lua.stringToNumber("a"));
    try expectError(error.LuaError, lua.stringToNumber("1.a"));
    try expectError(error.LuaError, lua.stringToNumber(""));
}

test "absIndex" {
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
    _ = try lua.getGlobal("f");

    const writer = struct {
        fn inner(l: *Lua, buf: []const u8, data: *anyopaque) bool {
            _ = l;
            var arr: *std.ArrayList(u8) = @ptrCast(@alignCast(data));
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
            const arr: *std.ArrayList(u8) = @ptrCast(@alignCast(data));
            return arr.items;
        }
    }.inner;

    // now load the function back onto the stack
    if (ziglua.lang == .lua51 or ziglua.lang == .luajit) {
        try lua.load(ziglua.wrap(reader), &buffer, "function");
    } else {
        try lua.load(ziglua.wrap(reader), &buffer, "function", .binary);
    }
    try expectEqual(.function, lua.typeOf(-1));

    // run the function (creating a new function)
    lua.pushInteger(5);
    try lua.protectedCall(.{ .args = 1, .results = 1 });

    // now call the new function (which should return the value + 5)
    lua.pushInteger(6);
    try lua.protectedCall(.{ .args = 1, .results = 1 });
    try expectEqual(11, try lua.toInteger(-1));
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
        try lua.setUserValue(1, 1);

        _ = lua.pushStringZ("test string");
        try lua.setUserValue(1, 2);

        try expectEqual(.number, try lua.getUserValue(1, 1));
        try expectEqual(1234.56, try lua.toNumber(-1));
        try expectEqual(.string, try lua.getUserValue(1, 2));
        try expectEqualStrings("test string", try lua.toString(-1));

        try expectError(error.LuaError, lua.setUserValue(1, 3));
        try expectError(error.LuaError, lua.getUserValue(1, 3));
    }
}

test "upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // counter from PIL
    const counter = struct {
        fn inner(l: *Lua) !i32 {
            var counter = try l.toInteger(Lua.upvalueIndex(1));
            counter += 1;
            l.pushInteger(counter);
            l.pushInteger(counter);
            l.replace(Lua.upvalueIndex(1));
            return 1;
        }
    }.inner;

    // Initialize the counter at 0
    lua.pushInteger(0);
    lua.pushClosure(ziglua.wrap(counter), 1);
    lua.setGlobal("counter");

    // call the function repeatedly, each time ensuring the result increases by one
    var expected: i32 = 1;
    while (expected <= 10) : (expected += 1) {
        _ = try lua.getGlobal("counter");
        lua.call(.{ .results = 1 });
        try expectEqual(expected, try lua.toInteger(-1));
        lua.pop(1);
    }
}

test "table traversal" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("t = { key = 'value', second = true, third = 1 }");
    _ = try lua.getGlobal("t");

    lua.pushNil();

    while (lua.next(1)) {
        switch (lua.typeOf(-1)) {
            .string => {
                try expectEqualStrings("key", try lua.toString(-2));
                try expectEqualStrings("value", try lua.toString(-1));
            },
            .boolean => {
                try expectEqualStrings("second", try lua.toString(-2));
                try expectEqual(true, lua.toBoolean(-1));
            },
            .number => {
                try expectEqualStrings("third", try lua.toString(-2));
                try expectEqual(1, try lua.toInteger(-1));
            },
            else => unreachable,
        }
        lua.pop(1);
    }
}

test "registry" {
    if (langIn(.{ .lua51, .luajit, .luau })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const key = "mykey";

    // store a string in the registry
    _ = lua.pushStringZ("hello there");
    lua.rawSetPtr(ziglua.registry_index, key);

    // get key from the registry
    _ = lua.rawGetPtr(ziglua.registry_index, key);
    try expectEqualStrings("hello there", try lua.toString(-1));
}

test "closing vars" {
    if (ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.openBase();

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
            _ = l.pushStringZ("makeError made an error");
            l.raiseError();
            return 0;
        }
    }.inner;

    lua.pushFunction(ziglua.wrap(makeError));
    try expectError(error.LuaRuntime, lua.protectedCall(.{}));
    try expectEqualStrings("makeError made an error", try lua.toString(-1));
}

fn continuation(l: *Lua, status: ziglua.Status, ctx: isize) i32 {
    _ = status;

    if (ctx == 5) {
        _ = l.pushStringZ("done");
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

    try expectEqualStrings("done", try thread.toString(-1));
}

fn continuation52(l: *Lua) !i32 {
    const ctxOrNull = try l.getContext();
    const ctx = ctxOrNull orelse 0;
    if (ctx == 5) {
        _ = l.pushStringZ("done");
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
        fn inner(l: *Lua) !i32 {
            return try continuation52(l);
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
    try expectEqualStrings("done", try thread.toString(-1));
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
    thread.pushFunction(func);
    if (ziglua.lang == .luau) {
        _ = try thread.resumeThread(null, 0);
    } else {
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
    _ = try thread.getGlobal("counter");

    var i: i32 = 1;
    while (i <= 5) : (i += 1) {
        try expectEqual(.yield, if (ziglua.lang == .lua51 or ziglua.lang == .luajit) try thread.resumeThread(0) else try thread.resumeThread(lua, 0));
        try expectEqual(i, thread.toInteger(-1));
        lua.pop(lua.getTop());
    }
    try expectEqual(.ok, if (ziglua.lang == .lua51 or ziglua.lang == .luajit) try thread.resumeThread(0) else try thread.resumeThread(lua, 0));
    try expectEqualStrings("done", try thread.toString(-1));
}

test "aux check functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.checkAny(1);
            _ = l.checkInteger(2);
            _ = l.checkNumber(3);
            _ = l.checkString(4);
            l.checkType(5, .boolean);
            _ = if (ziglua.lang == .lua52) l.checkUnsigned(6);
            return 0;
        }
    }.inner);

    lua.pushFunction(function);
    lua.protectedCall(.{ .args = 0 }) catch {
        try expectStringContains("argument #1", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.protectedCall(.{ .args = 1 }) catch {
        try expectStringContains("number expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.protectedCall(.{ .args = 2 }) catch {
        try expectStringContains("string expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    lua.protectedCall(.{ .args = 3 }) catch {
        try expectStringContains("string expected", try lua.toString(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function);
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.protectedCall(.{ .args = 4 }) catch {
        try expectStringContains("boolean expected", try lua.toString(-1));
        lua.pop(-1);
    };

    if (ziglua.lang == .lua52) {
        lua.pushFunction(function);
        lua.pushNil();
        lua.pushInteger(3);
        lua.pushNumber(4);
        _ = lua.pushString("hello world");
        lua.pushBoolean(true);
        lua.protectedCall(.{ .args = 5 }) catch {
            try expectEqualStrings("bad argument #6 to '?' (number expected, got no value)", try lua.toString(-1));
            lua.pop(-1);
        };
    }

    lua.pushFunction(function);
    // test pushFail here (currently acts the same as pushNil)
    if (ziglua.lang == .lua54) lua.pushFail() else lua.pushNil();
    lua.pushInteger(3);
    lua.pushNumber(4);
    _ = lua.pushString("hello world");
    lua.pushBoolean(true);
    if (ziglua.lang == .lua52) {
        lua.pushUnsigned(1);
        try lua.protectedCall(.{ .args = 6 });
    } else try lua.protectedCall(.{ .args = 5 });
}

test "aux opt functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = ziglua.wrap(struct {
        fn inner(l: *Lua) !i32 {
            try expectEqual(10, l.optInteger(1) orelse 10);
            try expectEqualStrings("zig", l.optString(2) orelse "zig");
            try expectEqual(1.23, l.optNumber(3) orelse 1.23);
            try expectEqualStrings("lang", l.optString(4) orelse "lang");
            return 0;
        }
    }.inner);

    lua.pushFunction(function);
    try lua.protectedCall(.{});

    lua.pushFunction(function);
    lua.pushInteger(10);
    _ = lua.pushString("zig");
    lua.pushNumber(1.23);
    _ = lua.pushStringZ("lang");
    try lua.protectedCall(.{ .args = 4 });
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

    lua.pushFunction(function);
    _ = lua.pushStringZ("one");
    try lua.protectedCall(.{ .args = 1, .results = 1 });
    try expectEqual(1, try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function);
    _ = lua.pushStringZ("two");
    try lua.protectedCall(.{ .args = 1, .results = 1 });
    try expectEqual(2, try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function);
    _ = lua.pushStringZ("three");
    try lua.protectedCall(.{ .args = 1, .results = 1 });
    try expectEqual(3, try lua.toInteger(-1));
    lua.pop(1);

    // try the default now
    lua.pushFunction(function);
    try lua.protectedCall(.{ .results = 1 });
    try expectEqual(1, try lua.toInteger(-1));
    lua.pop(1);

    // check the raised error
    lua.pushFunction(function);
    _ = lua.pushStringZ("unknown");
    try expectError(error.LuaRuntime, lua.protectedCall(.{ .args = 1, .results = 1 }));
    try expectStringContains("(invalid option 'unknown')", try lua.toString(-1));
}

test "get global fail" {
    if (ziglua.lang != .lua54) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectError(error.LuaError, lua.getGlobal("foo"));
}

test "globalSub" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.globalSub("-gity -!", "-", "zig");
    try expectEqualStrings("ziggity zig!", try lua.toString(-1));
}

test "loadBuffer" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    if (ziglua.lang == .lua51 or ziglua.lang == .luajit) {
        _ = try lua.loadBuffer("global = 10", "chunkname");
    } else _ = try lua.loadBuffer("global = 10", "chunkname", .text);

    try lua.protectedCall(.{ .args = 0, .results = ziglua.mult_return });
    _ = try lua.getGlobal("global");
    try expectEqual(10, try lua.toInteger(-1));
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

    lua.pushFunction(whereFn);
    lua.setGlobal("whereFn");

    try lua.doString(
        \\
        \\ret = whereFn()
    );

    _ = try lua.getGlobal("ret");
    try expectEqualStrings("[string \"...\"]:2: ", try lua.toString(-1));
}

test "ref" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.LuaError, lua.ref(ziglua.registry_index));
    try expectEqual(0, lua.getTop());

    _ = lua.pushString("Hello there");
    const ref = try lua.ref(ziglua.registry_index);

    _ = lua.rawGetIndex(ziglua.registry_index, ref);
    try expectEqualStrings("Hello there", try lua.toString(-1));

    lua.unref(ziglua.registry_index, ref);
}

test "ref luau" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.LuaError, lua.ref(1));
    try expectEqual(1, lua.getTop());

    // In luau lua.ref does not pop the item from the stack
    // and the data is stored in the registry_index by default
    _ = lua.pushString("Hello there");
    const ref = try lua.ref(2);

    _ = lua.rawGetIndex(ziglua.registry_index, ref);
    try expectEqualStrings("Hello there", try lua.toString(-1));

    lua.unref(ref);
}

test "metatables" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("f = function() return 10 end");

    try lua.newMetatable("mt");

    if (!langIn(.{ .lua51, .luajit, .luau })) {
        _ = lua.getMetatableRegistry("mt");
        try expect(lua.compare(1, 2, .eq));
        lua.pop(1);
    }

    // set the len metamethod to the function f
    _ = try lua.getGlobal("f");
    lua.setField(1, "__len");

    lua.newTable();
    if (!langIn(.{ .lua51, .luajit, .luau })) {
        lua.setMetatableRegistry("mt");
    } else {
        _ = lua.getField(ziglua.registry_index, "mt");
        lua.setMetatable(-2);
    }

    try lua.callMeta(-1, "__len");
    try expectEqual(10, try lua.toNumber(-1));
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

    lua.pushFunction(argCheck);
    try expectError(error.LuaRuntime, lua.protectedCall(.{}));

    const raisesError = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.raiseErrorStr("some error %s!", .{"zig"});
            unreachable;
        }
    }.inner);

    lua.pushFunction(raisesError);
    try expectError(error.LuaRuntime, lua.protectedCall(.{}));
    try expectEqualStrings("some error zig!", try lua.toString(-1));

    if (ziglua.lang != .lua54) return;

    const argExpected = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.argExpected(false, 1, "string");
            return 0;
        }
    }.inner);

    lua.pushFunction(argExpected);
    try expectError(error.LuaRuntime, lua.protectedCall(.{}));
}

test "traceback" {
    if (langIn(.{ .lua51, .luajit, .luau })) return;

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

    _ = try lua.getGlobal("res");
    try expectEqualStrings("\nstack traceback:\n\t[string \"res = tracebackFn()\"]:1: in main chunk", try lua.toString(-1));
}

test "getSubtable" {
    if (langIn(.{ .lua51, .luajit, .luau })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\a = {
        \\  b = {},
        \\}
    );
    _ = try lua.getGlobal("a");

    // get the subtable a.b
    _ = lua.getSubtable(-1, "b");

    // fail to get the subtable a.c (but it is created)
    try expectEqual(false, lua.getSubtable(-2, "c"));

    // now a.c will return true
    try expectEqual(true, lua.getSubtable(-3, "c"));
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
                _ = l.pushString("error!");
                l.raiseError();
            }
            if (ptr.b != 3.14) {
                _ = l.pushString("error!");
                l.raiseError();
            }
            return 1;
        }
    }.inner);

    lua.pushFunction(checkUdata);

    {
        var t = if (ziglua.lang == .lua54) lua.newUserdata(Type, 0) else lua.newUserdata(Type);
        if (langIn(.{ .lua51, .luajit, .luau })) {
            _ = lua.getField(ziglua.registry_index, "Type");
            lua.setMetatable(-2);
        } else lua.setMetatableRegistry("Type");

        t.a = 1234;
        t.b = 3.14;

        // call checkUdata asserting that the udata passed in with the
        // correct metatable and values
        try lua.protectedCall(.{ .args = 1, .results = 1 });
    }

    if (langIn(.{ .lua51, .luajit, .luau })) return;

    const testUdata = ziglua.wrap(struct {
        fn inner(l: *Lua) !i32 {
            const ptr = try l.testUserdata(Type, 1, "Type");
            if (ptr.a != 1234) {
                _ = l.pushString("error!");
                l.raiseError();
            }
            if (ptr.b != 3.14) {
                _ = l.pushString("error!");
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
        try lua.protectedCall(.{ .args = 1 });
    }
}

test "userdata slices" {
    const Integer = ziglua.Integer;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.newMetatable("FixedArray");

    // create an array of 10
    const slice = if (ziglua.lang == .lua54) lua.newUserdataSlice(Integer, 10, 0) else lua.newUserdataSlice(Integer, 10);
    if (langIn(.{ .lua51, .luajit, .luau })) {
        _ = lua.getField(ziglua.registry_index, "FixedArray");
        lua.setMetatable(-2);
    } else lua.setMetatableRegistry("FixedArray");

    for (slice, 1..) |*item, index| {
        item.* = @intCast(index);
    }

    const udataFn = struct {
        fn inner(l: *Lua) !i32 {
            _ = l.checkUserdataSlice(Integer, 1, "FixedArray");

            if (!langIn(.{ .lua51, .luajit, .luau })) _ = try l.testUserdataSlice(Integer, 1, "FixedArray");

            const arr = try l.toUserdataSlice(Integer, 1);
            for (arr, 1..) |item, index| {
                if (item != index) l.raiseErrorStr("something broke!", .{});
            }

            return 0;
        }
    }.inner;

    lua.pushFunction(ziglua.wrap(udataFn));
    lua.pushValue(2);

    try lua.protectedCall(.{ .args = 1 });
}

test "function environments" {
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("function test() return x end");

    // set the global _G.x to be 10
    lua.pushInteger(10);
    lua.setGlobal("x");

    _ = try lua.getGlobal("test");
    try lua.protectedCall(.{ .results = 1 });
    try testing.expectEqual(10, lua.toInteger(1));
    lua.pop(1);

    // now set the functions table to have a different value of x
    _ = try lua.getGlobal("test");
    lua.newTable();
    lua.pushInteger(20);
    lua.setField(2, "x");
    try lua.setFnEnvironment(1);

    try lua.protectedCall(.{ .results = 1 });
    try testing.expectEqual(20, lua.toInteger(1));
    lua.pop(1);

    _ = try lua.getGlobal("test");
    lua.getFnEnvironment(1);
    _ = lua.getField(2, "x");
    try testing.expectEqual(20, lua.toInteger(3));
}

test "objectLen" {
    if (ziglua.lang != .lua51 and ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.pushStringZ("lua");
    try testing.expectEqual(3, lua.objectLen(-1));
}

// Debug Library

test "debug interface" {
    if (langIn(.{ .lua51, .luajit, .luau })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  local y = x * 2
        \\  y = y + 2
        \\  return x + y
        \\end
    );
    _ = try lua.getGlobal("f");

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
        fn inner(l: *Lua, event: ziglua.Event, i: *DebugInfo) !void {
            switch (event) {
                .call => {
                    if (ziglua.lang == .lua54) l.getInfo(.{ .l = true, .r = true }, i) else l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 2) std.debug.panic("Expected line to be 2", .{});
                    _ = if (ziglua.lang == .lua54) try l.getLocal(i, i.first_transfer) else try l.getLocal(i, 1);
                    if ((try l.toNumber(-1)) != 3) std.debug.panic("Expected x to equal 3", .{});
                },
                .line => if (i.current_line.? == 4) {
                    // modify the value of y to be 0 right before returning
                    l.pushNumber(0);
                    _ = try l.setLocal(i, 2);
                },
                .ret => {
                    if (ziglua.lang == .lua54) l.getInfo(.{ .l = true, .r = true }, i) else l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 4) std.debug.panic("Expected line to be 4", .{});
                    _ = if (ziglua.lang == .lua54) try l.getLocal(i, i.first_transfer) else try l.getLocal(i, 1);
                    if ((try l.toNumber(-1)) != 3) std.debug.panic("Expected result to equal 3", .{});
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

    _ = try lua.getGlobal("f");
    lua.pushNumber(3);
    try lua.protectedCall(.{ .args = 1, .results = 1 });
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
    _ = try lua.getGlobal("f");

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
        fn inner(l: *Lua, event: ziglua.Event, i: *DebugInfo) !void {
            switch (event) {
                .call => {
                    l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 2) std.debug.panic("Expected line to be 2", .{});
                    _ = try l.getLocal(i, 1);
                    if ((try l.toNumber(-1)) != 3) std.debug.panic("Expected x to equal 3", .{});
                },
                .line => if (i.current_line.? == 4) {
                    // modify the value of y to be 0 right before returning
                    l.pushNumber(0);
                    _ = try l.setLocal(i, 2);
                },
                .ret => {
                    l.getInfo(.{ .l = true }, i);
                    if (i.current_line.? != 4) std.debug.panic("Expected line to be 4", .{});
                    _ = try l.getLocal(i, 1);
                    if ((try l.toNumber(-1)) != 3) std.debug.panic("Expected result to equal 3", .{});
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

    _ = try lua.getGlobal("f");
    lua.pushNumber(3);
    try lua.protectedCall(.{ .args = 1, .results = 1 });
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
    _ = try lua.getGlobal("addone");

    // index doesn't exist
    try expectError(error.LuaError, lua.getUpvalue(1, 2));

    // inspect the upvalue (should be x)
    try expectEqualStrings(if (ziglua.lang == .luau) "" else "x", try lua.getUpvalue(-1, 1));
    try expectEqual(1, try lua.toNumber(-1));
    lua.pop(1);

    // now make the function an "add five" function
    lua.pushNumber(5);
    _ = try lua.setUpvalue(-2, 1);

    // test a bad index (the valid one's result is unpredicable)
    if (ziglua.lang == .lua54) try expectError(error.LuaError, lua.upvalueId(-1, 2));

    // call the new function (should return 7)
    lua.pushNumber(2);
    try lua.protectedCall(.{ .args = 1, .results = 1 });
    try expectEqual(7, try lua.toNumber(-1));

    if (langIn(.{ .lua51, .luajit, .luau })) return;

    lua.pop(1);

    try lua.doString(
        \\addthree = f(3)
    );

    _ = try lua.getGlobal("addone");
    _ = try lua.getGlobal("addthree");

    // now addone and addthree share the same upvalue
    lua.upvalueJoin(-2, 1, -1, 1);
    try expect((try lua.upvalueId(-2, 1)) == try lua.upvalueId(-1, 1));
}

test "getstack" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectError(error.LuaError, lua.getStack(1));

    const function = struct {
        fn inner(l: *Lua) !i32 {
            // get info about calling lua function
            var info = try l.getStack(1);
            l.getInfo(.{ .n = true }, &info);
            try expectEqualStrings("g", info.name.?);
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
    try lua.protectedCall(.{ .results = 1 });
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
    try expectError(error.LuaError, lua.toUserdataTagged(Data, -1, 123));

    // should not fail
    _ = try lua.toUserdataTagged(Data, -1, 100);

    // Integer is not userdata, so userdataTag should fail.
    lua.pushInteger(13);
    try expectError(error.LuaError, lua.userdataTag(-1));
}

fn vectorCtor(l: *Lua) !i32 {
    const x = try l.toNumber(1);
    const y = try l.toNumber(2);
    const z = try l.toNumber(3);
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
    try lua.protectedCall(.{ .results = 1 });
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

test "useratom" {
    if (ziglua.lang != .luau) return;

    const useratomCb = struct {
        pub fn inner(str: []const u8) i16 {
            if (std.mem.eql(u8, str, "method_one")) {
                return 0;
            } else if (std.mem.eql(u8, str, "another_method")) {
                return 1;
            }
            return -1;
        }
    }.inner;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.setUserAtomCallbackFn(ziglua.wrap(useratomCb));

    _ = lua.pushStringZ("unknownatom");
    _ = lua.pushStringZ("method_one");
    _ = lua.pushStringZ("another_method");

    const atom_idx0, const str0 = try lua.toStringAtom(-2);
    const atom_idx1, const str1 = try lua.toStringAtom(-1);
    const atom_idx2, const str2 = try lua.toStringAtom(-3);
    try testing.expect(std.mem.eql(u8, str0, "method_one"));
    try testing.expect(std.mem.eql(u8, str1, "another_method"));
    try testing.expect(std.mem.eql(u8, str2, "unknownatom")); // should work, but returns -1 for atom idx

    try expectEqual(0, atom_idx0);
    try expectEqual(1, atom_idx1);
    try expectEqual(-1, atom_idx2);

    lua.pushInteger(13);
    try expectError(error.LuaError, lua.toStringAtom(-1));
}

test "namecall" {
    if (ziglua.lang != .luau) return;

    const funcs = struct {
        const dot_idx: i32 = 0;
        const sum_idx: i32 = 1;

        // The useratom callback to initially form a mapping from method names to
        // integer indices. The indices can then be used to quickly dispatch the right
        // method in namecalls without needing to perform string compares.
        pub fn useratomCb(str: []const u8) i16 {
            if (std.mem.eql(u8, str, "dot")) {
                return dot_idx;
            }
            if (std.mem.eql(u8, str, "sum")) {
                return sum_idx;
            }
            return -1;
        }

        pub fn vectorNamecall(l: *Lua) i32 {
            const atom_idx, _ = l.namecallAtom() catch {
                l.raiseErrorStr("%s is not a valid vector method", .{l.checkString(1).ptr});
            };
            switch (atom_idx) {
                dot_idx => {
                    const a = l.checkVector(1);
                    const b = l.checkVector(2);
                    l.pushNumber(a[0] * b[0] + a[1] * b[1] + a[2] * b[2]); // vec3 dot
                    return 1;
                },
                sum_idx => {
                    const a = l.checkVector(1);
                    l.pushNumber(a[0] + a[1] + a[2]);
                    return 1;
                },
                else => unreachable,
            }
        }
    };

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.setUserAtomCallbackFn(ziglua.wrap(funcs.useratomCb));

    lua.register("vector", ziglua.wrap(vectorCtor));
    lua.pushVector(0, 0, 0);

    try lua.newMetatable("vector");
    _ = lua.pushStringZ("__namecall");
    lua.pushFunctionNamed(ziglua.wrap(funcs.vectorNamecall), "vector_namecall");
    lua.setTable(-3);

    lua.setReadonly(-1, true);
    lua.setMetatable(-2);

    // Vector setup, try some lua code on them.
    try lua.doString(
        \\local a = vector(1, 2, 3)
        \\local b = vector(3, 2, 1)
        \\return a:dot(b)
    );
    const d = try lua.toNumber(-1);
    lua.pop(-1);
    try expectEqual(10, d);

    try lua.doString(
        \\local a = vector(1, 2, 3)
        \\return a:sum()
    );
    const s = try lua.toNumber(-1);
    lua.pop(-1);
    try expectEqual(6, s);
}

test "toAny" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    //int
    lua.pushInteger(100);
    const my_int = try lua.toAny(i32, -1);
    try testing.expect(my_int == 100);

    //bool
    lua.pushBoolean(true);
    const my_bool = try lua.toAny(bool, -1);
    try testing.expect(my_bool);

    //float
    lua.pushNumber(100.0);
    const my_float = try lua.toAny(f32, -1);
    try testing.expect(my_float == 100.0);

    //[]const u8
    _ = lua.pushStringZ("hello world");
    const my_string_1 = try lua.toAny([]const u8, -1);
    try testing.expect(std.mem.eql(u8, my_string_1, "hello world"));

    //[:0]const u8
    _ = lua.pushStringZ("hello world");
    const my_string_2 = try lua.toAny([:0]const u8, -1);
    try testing.expect(std.mem.eql(u8, my_string_2, "hello world"));

    //[*:0]const u8
    _ = lua.pushStringZ("hello world");
    const my_string_3 = try lua.toAny([*:0]const u8, -1);
    const end = std.mem.indexOfSentinel(u8, 0, my_string_3);
    try testing.expect(std.mem.eql(u8, my_string_3[0..end], "hello world"));

    //ptr
    var my_value: i32 = 100;
    _ = lua.pushLightUserdata(&my_value);
    const my_ptr = try lua.toAny(*i32, -1);
    try testing.expect(my_ptr.* == my_value);

    //optional
    lua.pushNil();
    const maybe = try lua.toAny(?i32, -1);
    try testing.expect(maybe == null);

    //enum
    const MyEnumType = enum { hello, goodbye };
    _ = lua.pushStringZ("hello");
    const my_enum = try lua.toAny(MyEnumType, -1);
    try testing.expect(my_enum == MyEnumType.hello);

    //void
    try lua.doString("value = {}\nvalue_err = {a = 5}");
    _ = try lua.getGlobal("value");
    try testing.expectEqual(void{}, try lua.toAny(void, -1));
    _ = try lua.getGlobal("value_err");
    try testing.expectError(error.LuaVoidTableIsNotEmpty, lua.toAny(void, -1));
}

test "toAny struct" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = struct {
        foo: i32,
        bar: bool,
        bizz: []const u8 = "hi",
    };
    try lua.doString("value = {[\"foo\"] = 10, [\"bar\"] = false}");
    const lua_type = try lua.getGlobal("value");
    try testing.expect(lua_type == .table);
    const my_struct = try lua.toAny(MyType, 1);
    try testing.expect(std.meta.eql(
        my_struct,
        MyType{ .foo = 10, .bar = false },
    ));
}

test "toAny mutable string" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    //[] u8
    _ = lua.pushStringZ("hello world");
    const parsed = try lua.toAnyAlloc([]u8, -1);
    defer parsed.deinit();

    const my_string = parsed.value;

    try testing.expect(std.mem.eql(u8, my_string, "hello world"));
}

test "toAny mutable string in struct" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = struct {
        name: []u8,
        sentinel: [:0]u8,
        bar: bool,
    };
    try lua.doString("value = {[\"name\"] = \"hi\", [\"sentinel\"] = \"ss\", [\"bar\"] = false}");
    const lua_type = try lua.getGlobal("value");
    try testing.expect(lua_type == .table);
    const parsed = try lua.toAnyAlloc(MyType, 1);
    defer parsed.deinit();

    const my_struct = parsed.value;

    var name: [2]u8 = .{ 'h', 'i' };
    var sentinel: [2:0]u8 = .{ 's', 's' };

    try testing.expectEqualDeep(
        MyType{ .name = &name, .sentinel = &sentinel, .bar = false },
        my_struct,
    );
}

test "toAny struct recursive" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = struct {
        foo: i32 = 10,
        bar: bool = false,
        bizz: []const u8 = "hi",
        meep: struct { a: ?i7 = null } = .{},
    };

    try lua.doString(
        \\value = {
        \\  ["foo"] = 10,
        \\  ["bar"] = false,
        \\  ["bizz"] = "hi",
        \\  ["meep"] = {
        \\    ["a"] = nil
        \\  }
        \\}
    );

    _ = try lua.getGlobal("value");
    const my_struct = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{}, my_struct);
}

test "toAny tagged union" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = union(enum) {
        a: i32,
        b: bool,
        c: []const u8,
        d: struct { t0: f64, t1: f64 },
    };

    try lua.doString(
        \\value0 = {
        \\  ["c"] = "Hello, world!",
        \\}
        \\value1 = {
        \\  ["d"] = {t0 = 5.0, t1 = -3.0},
        \\}
        \\value2 = {
        \\  ["a"] = 1000,
        \\}
    );

    _ = try lua.getGlobal("value0");
    const my_struct0 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{ .c = "Hello, world!" }, my_struct0);

    _ = try lua.getGlobal("value1");
    const my_struct1 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{ .d = .{ .t0 = 5.0, .t1 = -3.0 } }, my_struct1);

    _ = try lua.getGlobal("value2");
    const my_struct2 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(MyType{ .a = 1000 }, my_struct2);
}

test "toAny slice" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const program =
        \\list = {1, 2, 3, 4, 5}
    ;
    try lua.doString(program);
    _ = try lua.getGlobal("list");
    const sliced = try lua.toAnyAlloc([]u32, -1);
    defer sliced.deinit();

    try testing.expect(
        std.mem.eql(u32, &[_]u32{ 1, 2, 3, 4, 5 }, sliced.value),
    );
}

test "toAny array" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const arr: [5]?u32 = .{ 1, 2, null, 4, 5 };
    const program =
        \\array= {1, 2, nil, 4, 5}
    ;
    try lua.doString(program);
    _ = try lua.getGlobal("array");
    const array = try lua.toAny([5]?u32, -1);
    try testing.expectEqual(arr, array);
}

test "toAny vector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const vec = @Vector(4, bool){ true, false, false, true };
    const program =
        \\vector= {true, false, false, true}
    ;
    try lua.doString(program);
    _ = try lua.getGlobal("vector");
    const vector = try lua.toAny(@Vector(4, bool), -1);
    try testing.expectEqual(vec, vector);
}

test "pushAny" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    //int
    try lua.pushAny(1);
    const my_int = try lua.toInteger(-1);
    try testing.expect(my_int == 1);

    //float
    try lua.pushAny(1.0);
    const my_float = try lua.toNumber(-1);
    try testing.expect(my_float == 1.0);

    //bool
    try lua.pushAny(true);
    const my_bool = lua.toBoolean(-1);
    try testing.expect(my_bool);

    //string literal
    try lua.pushAny("hello world");
    const value = try lua.toString(-1);
    const end = std.mem.indexOfSentinel(u8, 0, value);
    try testing.expect(std.mem.eql(u8, value[0..end], "hello world"));

    //null
    try lua.pushAny(null);
    try testing.expect(try lua.toAny(?f32, -1) == null);

    //optional
    const my_optional: ?i32 = -1;
    try lua.pushAny(my_optional);
    try testing.expect(try lua.toAny(?i32, -1) == my_optional);

    //enum
    const MyEnumType = enum { hello, goodbye };
    try lua.pushAny(MyEnumType.goodbye);
    const my_enum = try lua.toAny(MyEnumType, -1);
    try testing.expect(my_enum == MyEnumType.goodbye);

    //void
    try lua.pushAny(void{});
    try testing.expectEqual(void{}, try lua.toAny(void, -1));
}

test "pushAny struct" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = struct {
        foo: i32 = 1,
        bar: bool = false,
        bizz: []const u8 = "hi",
    };
    try lua.pushAny(MyType{});
    const value = try lua.toAny(MyType, -1);
    try testing.expect(std.mem.eql(u8, value.bizz, (MyType{}).bizz));
    try testing.expect(value.foo == (MyType{}).foo);
    try testing.expect(value.bar == (MyType{}).bar);
}

test "pushAny tagged union" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const MyType = union(enum) {
        a: i32,
        b: bool,
        c: []const u8,
        d: struct { t0: f64, t1: f64 },
    };

    const t0 = MyType{ .d = .{ .t0 = 5.0, .t1 = -3.0 } };
    try lua.pushAny(t0);
    const value0 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(t0, value0);

    const t1 = MyType{ .c = "Hello, world!" };
    try lua.pushAny(t1);
    const value1 = try lua.toAny(MyType, -1);
    try testing.expectEqualDeep(t1, value1);
}

test "pushAny toAny slice/array/vector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var my_array = [_]u32{ 1, 2, 3, 4, 5 };
    const my_slice: []u32 = my_array[0..];
    const my_vector: @Vector(5, u32) = .{ 1, 2, 3, 4, 5 };
    try lua.pushAny(my_slice);
    try lua.pushAny(my_array);
    try lua.pushAny(my_vector);
    const vector = try lua.toAny(@TypeOf(my_vector), -1);
    const array = try lua.toAny(@TypeOf(my_array), -2);
    const slice = try lua.toAnyAlloc(@TypeOf(my_slice), -3);
    defer slice.deinit();

    try testing.expectEqual(my_array, array);
    try testing.expectEqualDeep(my_slice, slice.value);
    try testing.expectEqual(my_vector, vector);
}

fn foo(a: i32, b: i32) i32 {
    return a + b;
}

fn bar(a: i32, b: i32) !i32 {
    if (a > b) return error.wrong;
    return a + b;
}

test "autoPushFunction" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    lua.autoPushFunction(foo);
    lua.setGlobal("foo");

    lua.autoPushFunction(bar);
    lua.setGlobal("bar");

    try lua.doString(
        \\result = foo(1, 2)
    );
    try lua.doString(
        \\local status, result = pcall(bar, 1, 2)
    );

    //automatic api construction
    const my_api = .{
        .foo = foo,
        .bar = bar,
    };

    try lua.pushAny(my_api);
    lua.setGlobal("api");

    try lua.doString(
        \\api.foo(1, 2)
    );
}

test "autoCall" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const program =
        \\function add(a, b)
        \\   return a + b
        \\end
    ;

    try lua.doString(program);

    for (0..100) |_| {
        const sum = try lua.autoCall(usize, "add", .{ 1, 2 });
        try std.testing.expect(3 == sum);
    }

    for (0..100) |_| {
        const sum = try lua.autoCallAlloc(usize, "add", .{ 1, 2 });
        defer sum.deinit();
        try std.testing.expect(3 == sum.value);
    }
}

test "autoCall stress test" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const program =
        \\function add(a, b)
        \\   return a + b
        \\end
        \\
        \\
        \\function KeyBindings()
        \\
        \\   local bindings = {
        \\      {['name'] = 'player_right', ['key'] = 'a'},
        \\      {['name'] = 'player_left',  ['key'] = 'd'},
        \\      {['name'] = 'player_up',    ['key'] = 'w'},
        \\      {['name'] = 'player_down',  ['key'] = 's'},
        \\      {['name'] = 'zoom_in',      ['key'] = '='},
        \\      {['name'] = 'zoom_out',     ['key'] = '-'},
        \\      {['name'] = 'debug_mode',   ['key'] = '/'},
        \\   }
        \\
        \\   return bindings
        \\end
    ;

    try lua.doString(program);

    const ConfigType = struct {
        name: []const u8,
        key: []const u8,
        shift: bool = false,
        control: bool = false,
    };

    for (0..100) |_| {
        const sum = try lua.autoCallAlloc([]ConfigType, "KeyBindings", .{});
        defer sum.deinit();
    }
}

test "get set" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.set("hello", true);
    try testing.expect(try lua.get(bool, "hello"));

    try lua.set("world", 1000);
    try testing.expect(try lua.get(u64, "world") == 1000);

    try lua.set("foo", 'a');
    try testing.expect(try lua.get(u8, "foo") == 'a');
}

test "array of strings" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const program =
        \\function strings()
        \\   return {"hello", "world", "my name", "is foobar"}
        \\end
    ;

    try lua.doString(program);

    for (0..100) |_| {
        const strings = try lua.autoCallAlloc([]const []const u8, "strings", .{});
        defer strings.deinit();
    }
}

test "loadFile binary mode" {
    if (langIn(.{ .lua51, .luajit, .luau })) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // Should fail to load a lua file as a binary file
    try expectError(error.LuaSyntax, lua.loadFile("src/test.lua", .binary));
}

test "doFile" {
    if (ziglua.lang == .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // should set the variable GLOBAL to "testing"
    try lua.doFile("src/test.lua");

    try expectEqualStrings("testing", try lua.get([]const u8, "GLOBAL"));
}

test "define" {
    const expected =
        \\---@class (exact) T
        \\---@field foo integer
        \\
        \\---@class (exact) TestType
        \\---@field a integer
        \\---@field b number
        \\---@field c boolean
        \\---@field d SubType
        \\---@field e Bippity[]
        \\
        \\---@class (exact) SubType
        \\---@field foo integer
        \\---@field bar boolean
        \\---@field bip MyEnum
        \\---@field bap MyEnum[] | nil
        \\
        \\---@alias MyEnum
        \\---|' "asdf" '
        \\---|' "fdsa" '
        \\---|' "qwer" '
        \\---|' "rewq" '
        \\
        \\---@class (exact) Bippity
        \\---@field A integer | nil
        \\---@field B lightuserdata
        \\---@field C string
        \\---@field D lightuserdata | nil
        \\
        \\---@class (exact) Foo
        \\---@field far MyEnum
        \\---@field near SubType
        \\
        \\
    ;

    const T = struct { foo: i32 };
    const MyEnum = enum { asdf, fdsa, qwer, rewq };
    const SubType = struct { foo: i32, bar: bool, bip: MyEnum, bap: ?[]MyEnum };
    const Bippity = struct { A: ?i32, B: *bool, C: []const u8, D: ?*SubType };
    const TestType = struct { a: i32, b: f32, c: bool, d: SubType, e: [10]Bippity };
    const Foo = struct { far: MyEnum, near: SubType };

    const a = std.testing.allocator;

    var state = ziglua.def.DefineState.init(a);
    defer state.deinit();

    const to_define: []const type = &.{ T, TestType, Foo };
    inline for (to_define) |my_type| {
        _ = try ziglua.def.addClass(&state, my_type);
    }

    var buffer: [10000]u8 = .{0} ** 10000;
    var buffer_stream = std.io.fixedBufferStream(&buffer);
    var writer = buffer_stream.writer();

    for (state.definitions.items) |def| {
        try writer.writeAll(def.items);
        try writer.writeAll("\n");
    }

    try std.testing.expectEqualSlices(u8, expected, buffer_stream.getWritten());
}

test "interrupt" {
    if (ziglua.lang != .luau) return;

    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const interrupt_handler = struct {
        var times_called: i32 = 0;

        pub fn inner(l: *Lua, _: i32) void {
            times_called += 1;
            l.setInterruptCallbackFn(null);
            l.raiseInterruptErrorStr("interrupted", .{});
        }
    };

    // Luau only checks for an interrupt callback at certain points, including function calls
    try lua.doString(
        \\function add(a, b)
        \\   return a + b
        \\end
    );
    lua.setInterruptCallbackFn(ziglua.wrap(interrupt_handler.inner));

    const expected_err = lua.doString(
        \\c = add(1, 2)
    );
    try testing.expectError(error.LuaRuntime, expected_err);
    try testing.expectEqual(1, interrupt_handler.times_called);

    // Handler should have removed itself
    try lua.doString(
        \\c = add(1, 2)
    );
    try testing.expectEqual(1, interrupt_handler.times_called);
}

test "error union for CFn" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const fails = struct {
        fn inner(l: *Lua) !i32 {
            // Test returning some error union
            _ = l.toInteger(1) catch return error.MissingInteger;
            return 0;
        }
    }.inner;

    // This will fail because there is no argument passed
    lua.pushFunction(ziglua.wrap(fails));
    lua.protectedCall(.{}) catch {
        // Get the error string
        try expectEqualStrings("MissingInteger", try lua.toString(-1));
    };
}
