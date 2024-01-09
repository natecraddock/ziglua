const std = @import("std");
const testing = std.testing;
const ziglua = @import("ziglua");

const AllocFn = ziglua.AllocFn;
const Buffer = ziglua.Buffer;
const DebugInfo = ziglua.DebugInfo;
const Error = ziglua.Error;
const Event = ziglua.Event;
const Integer = ziglua.Integer;
const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;
const Number = ziglua.Number;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;
const panic = std.debug.panic;

fn expectEqualStringsSentinel(expected: []const u8, actual: [*:0]const u8) !void {
    return expectEqualStrings(expected, std.mem.span(actual));
}

// until issue #1717 we need to use the struct workaround
const add = struct {
    fn addInner(l: *Lua) i32 {
        const a = l.toInteger(1) catch unreachable;
        const b = l.toInteger(2) catch unreachable;
        l.pushInteger(a + b);
        return 1;
    }
}.addInner;

const sub = struct {
    fn subInner(l: *Lua) i32 {
        const a = l.toInteger(1) catch unreachable;
        const b = l.toInteger(2) catch unreachable;
        l.pushInteger(a - b);
        return 1;
    }
}.subInner;

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
    try expectEqual(@as(AllocFn, alloc), lua.getAllocFn(&data));
}

test "standard library loading" {
    // open a subset of standard libraries with Zig wrapper
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.open(.{
            .base = true,
            .package = true,
            .string = true,
            .table = true,
            .math = true,
            .io = true,
            .os = true,
            .debug = true,
        });
    }

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
    }
}

test "type of and getting values" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var value: i32 = 0;

    lua.pushNil();
    try expect(lua.isNil(1));
    try expect(lua.isNoneOrNil(1));
    try expect(lua.isNoneOrNil(2));
    try expect(lua.isNone(2));
    lua.pop(1);

    lua.pushBoolean(true);
    lua.newTable();
    lua.pushInteger(1);
    lua.pushLightUserdata(&value);
    lua.pushNil();
    lua.pushNumber(0.1);
    _ = lua.pushThread();
    lua.pushString("all your codebase are belong to us");
    lua.pushFunction(ziglua.wrap(add), "add");
    lua.pushBytes("hello world");
    _ = lua.pushFString("%s %s %d", .{ "hello", "world", @as(i32, 10) });
    lua.pushValue(1);

    // test both typeof and is functions
    try expectEqual(LuaType.boolean, lua.typeOf(1));
    try expectEqual(LuaType.table, lua.typeOf(2));
    try expectEqual(LuaType.number, lua.typeOf(3));
    try expectEqual(LuaType.light_userdata, lua.typeOf(4));
    try expectEqual(LuaType.nil, lua.typeOf(5));
    try expectEqual(LuaType.number, lua.typeOf(6));
    try expectEqual(LuaType.thread, lua.typeOf(7));
    try expectEqual(LuaType.string, lua.typeOf(8));
    try expectEqual(LuaType.function, lua.typeOf(9));
    try expectEqual(LuaType.string, lua.typeOf(10));
    try expectEqual(LuaType.string, lua.typeOf(11));
    try expectEqual(LuaType.boolean, lua.typeOf(12));

    try expect(lua.isBoolean(1));
    try expect(lua.isTable(2));
    try expect(lua.isNumber(3));
    try expect(lua.isLightUserdata(4));
    try expect(lua.isUserdata(4));
    try expect(lua.isNil(5));
    try expect(lua.isNumber(6));
    try expect(lua.isThread(7));
    try expect(lua.isString(8));
    try expect(lua.isCFunction(9));
    try expect(lua.isFunction(9));
    try expect(lua.isString(10));
    try expect(lua.isString(11));
    try expect(lua.isBoolean(12));

    try expectEqualStrings("hello world 10", std.mem.span(try lua.toString(11)));

    // the created thread should equal the main thread (but created thread has no allocator ref)
    try expectEqual(lua.state, (try lua.toThread(7)).state);
    try expectEqual(@as(ziglua.CFn, ziglua.wrap(add)), try lua.toCFunction(9));

    try expectEqual(@as(Number, 0.1), try lua.toNumber(6));
    try expectEqual(@as(Integer, 1), try lua.toInteger(3));

    try expectEqualStrings("number", lua.typeNameIndex(3));
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
}

test "executing string contents" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();
    lua.openLibs();

    try lua.loadString("f = function(x) return x + 10 end");
    try lua.protectedCall(0, 0, 0);
    try lua.loadString("a = f(2)");
    try lua.protectedCall(0, 0, 0);

    try expectEqual(LuaType.function, lua.getGlobal("f"));
    try expectEqual(LuaType.function, lua.typeOf(-1));
    lua.pop(1);
    try expectEqual(LuaType.number, lua.getGlobal("a"));
    try expectEqual(LuaType.number, lua.typeOf(-1));
    try expectEqual(@as(i64, 12), try lua.toInteger(1));

    try expectError(error.Fail, lua.loadString("bad syntax"));
    try lua.loadString("a = g()");
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
}

test "filling and checking the stack" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectEqual(@as(i32, 0), lua.getTop());

    // We want to push 30 values onto the stack
    // this should work without fail
    try lua.checkStack(30);

    var count: i32 = 0;
    while (count < 30) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(@as(i32, 30), lua.getTop());

    // this should fail (beyond max stack size)
    try expectError(error.Fail, lua.checkStack(1_000_000));

    // this is small enough it won't fail (would raise an error if it did)
    lua.checkStackErr(40, null);
    while (count < 40) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(@as(i32, 40), lua.getTop());
}

test "comparisions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushInteger(1);
    lua.pushInteger(2);

    try testing.expect(!lua.equal(1, 2));
    try testing.expect(lua.lessThan(1, 2));

    lua.pushInteger(2);

    try testing.expect(lua.equal(2, 3));
}

test "stack manipulation" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // add some numbers to manipulate
    var num: i32 = 1;
    while (num <= 10) : (num += 1) {
        lua.pushInteger(num);
    }
    try expectEqual(@as(i32, 10), lua.getTop());

    lua.setTop(12);
    try expectEqual(@as(i32, 12), lua.getTop());
    try expect(lua.isNil(-1));

    lua.remove(1);
    try expect(lua.isNil(-1));

    lua.insert(1);
    try expect(lua.isNil(1));

    lua.setTop(0);
    try expectEqual(@as(i32, 0), lua.getTop());
}

test "calling a function" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.register("zigadd", ziglua.wrap(add));
    _ = lua.getGlobal("zigadd");
    lua.pushInteger(10);
    lua.pushInteger(32);

    // protectedCall is safer, but we might as well exercise call when
    // we know it should be safe
    lua.call(2, 1);

    try expectEqual(@as(i64, 42), try lua.toInteger(1));
}

test "string buffers" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var buffer: Buffer = undefined;
    buffer.init(lua);

    buffer.addChar('z');
    buffer.addChar('i');
    buffer.addChar('g');
    buffer.addString("l");

    var str = buffer.prep();
    str[0] = 'u';
    str[1] = 'a';
    buffer.addSize(2);

    buffer.addBytes(" api ");
    lua.pushNumber(5.1);
    buffer.addValue();

    lua.pushBytes(" luau");
    buffer.addValueAny(-1);
    buffer.pushResult();
    try expectEqualStrings("ziglua api 5.1 luau", try lua.toBytes(-1));

    // now test a small buffer
    buffer = undefined;
    buffer.init(lua);
    var b = buffer.prep();
    b[0] = 'a';
    b[1] = 'b';
    b[2] = 'c';
    buffer.addSize(3);
    b = buffer.prep();
    @memcpy(b[0..23], "defghijklmnopqrstuvwxyz");
    buffer.pushResultSize(23);
    try expectEqualStrings("abcdefghijklmnopqrstuvwxyz", try lua.toBytes(-1));
    lua.pop(1);
}

test "function registration" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // register all functions as part of a table
    const funcs = [_]ziglua.FnReg{
        .{ .name = "add", .func = ziglua.wrap(add) },
    };
    lua.newTable();
    lua.registerFns(null, &funcs);

    try expectEqual(LuaType.function, lua.getField(-1, "add"));
    lua.pushInteger(1);
    lua.pushInteger(2);
    try lua.protectedCall(2, 1, 0);
    try expectEqual(@as(Integer, 3), try lua.toInteger(-1));
    lua.setTop(0);

    // register functions as globals in a library table
    lua.registerFns("testlib", &funcs);

    // testlib.add(1, 2)
    _ = lua.getGlobal("testlib");
    try expectEqual(LuaType.function, lua.getField(-1, "add"));
    lua.pushInteger(1);
    lua.pushInteger(2);
    try lua.protectedCall(2, 1, 0);
    try expectEqual(@as(Integer, 3), try lua.toInteger(-1));
}

test "concat" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushString("hello ");
    lua.pushNumber(10);
    lua.pushString(" wow!");
    lua.concat(3);

    try expectEqualStrings("hello 10 wow!", try lua.toBytes(-1));
}

test "garbage collector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // because the garbage collector is an opaque, unmanaged
    // thing, it is hard to test, so just run each function
    lua.gcStop();
    lua.gcCollect();
    lua.gcRestart();
    lua.gcStep();
    _ = lua.gcIsRunning();
    _ = lua.gcCount();
    _ = lua.gcCountB();
    _ = lua.gcSetGoal(10);
    _ = lua.gcSetStepMul(2);
    _ = lua.gcSetStepSize(1);
}

test "table access" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("a = { [1] = 'first', key = 'value', ['other one'] = 1234 }");
    _ = lua.getGlobal("a");

    _ = lua.rawGetIndex(1, 1);
    try expectEqual(LuaType.string, lua.typeOf(-1));
    try expectEqualStrings("first", try lua.toBytes(-1));

    _ = lua.rawGetIndex(1, 1);
    try expectEqual(LuaType.string, lua.typeOf(-1));
    try expectEqualStrings("first", try lua.toBytes(-1));

    lua.pushString("key");
    _ = lua.getTable(1);
    try expectEqual(LuaType.string, lua.typeOf(-1));
    try expectEqualStrings("value", try lua.toBytes(-1));

    lua.pushString("other one");
    _ = lua.rawGetTable(1);
    try expectEqual(LuaType.number, lua.typeOf(-1));
    try expectEqual(@as(Integer, 1234), try lua.toInteger(-1));

    // a.name = "ziglua"
    lua.pushString("name");
    lua.pushString("ziglua");
    lua.setTable(1);

    // a.lang = "zig"
    lua.pushString("lang");
    lua.pushString("zig");
    lua.rawSetTable(1);

    try expectError(error.Fail, lua.getMetatable(1));

    // create a metatable (it isn't a useful one)
    lua.newTable();
    lua.pushFunction(ziglua.wrap(add), "add");
    lua.setField(-2, "__len");
    lua.setMetatable(1);

    try lua.getMetatable(1);
    _ = try lua.getMetaField(1, "__len");
    try expectError(error.Fail, lua.getMetaField(1, "__index"));

    lua.pushBoolean(true);
    lua.setField(1, "bool");

    try lua.doString("b = a.bool");
    _ = lua.getGlobal("b");
    try expectEqual(LuaType.boolean, lua.typeOf(-1));
    try expect(lua.toBoolean(-1));

    // create array [1, 2, 3, 4, 5]
    lua.createTable(0, 0);
    var index: i32 = 1;
    while (index <= 5) : (index += 1) {
        lua.pushInteger(index);
        lua.rawSetIndex(-2, index);
    }

    // add a few more
    while (index <= 10) : (index += 1) {
        lua.pushInteger(index);
        lua.rawSetIndex(-2, index);
    }
}

test "threads" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var new_thread = lua.newThread();
    try expectEqual(@as(i32, 1), lua.getTop());
    try expectEqual(@as(i32, 0), new_thread.getTop());

    lua.pushInteger(10);
    lua.pushNil();

    lua.xMove(new_thread, 2);
    try expectEqual(@as(i32, 2), new_thread.getTop());
}

test "userdata and uservalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const Data = struct {
        val: i32,
        code: [4]u8,
    };

    // create a Lua-owned pointer to a Data
    var data = lua.newUserdata(Data);
    data.val = 1;
    @memcpy(&data.code, "abcd");

    try expectEqual(data, try lua.toUserdata(Data, 1));
    try expectEqual(@as(*const anyopaque, @ptrCast(data)), try lua.toPointer(1));
}

test "upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // counter from PIL
    const counter = struct {
        fn inner(l: *Lua) i32 {
            var counter = l.toInteger(Lua.upvalueIndex(1)) catch unreachable;
            counter += 1;
            l.pushInteger(counter);
            l.pushInteger(counter);
            l.replace(Lua.upvalueIndex(1));
            return 1;
        }
    }.inner;

    // Initialize the counter at 0
    lua.pushInteger(0);
    lua.pushClosure(ziglua.wrap(counter), "counter", 1);
    lua.setGlobal("counter");

    // call the function repeatedly, each time ensuring the result increases by one
    var expected: Integer = 1;
    while (expected <= 10) : (expected += 1) {
        _ = lua.getGlobal("counter");
        lua.call(0, 1);
        try expectEqual(expected, try lua.toInteger(-1));
        lua.pop(1);
    }
}

test "table traversal" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("t = { key = 'value', second = true, third = 1 }");
    _ = lua.getGlobal("t");

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
                try expectEqual(@as(Integer, 1), try lua.toInteger(-1));
            },
            else => unreachable,
        }
        lua.pop(1);
    }
}

test "raise error" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const makeError = struct {
        fn inner(l: *Lua) i32 {
            l.pushString("makeError made an error");
            l.raiseError();
            return 0;
        }
    }.inner;

    lua.pushFunction(ziglua.wrap(makeError), "makeError");
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
    try expectEqualStrings("makeError made an error", try lua.toBytes(-1));
}

test "yielding" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var thread = lua.newThread();
    thread.pushFunction(ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.pushInteger(1);
            return l.yield(1);
        }
    }.inner), "yieldfn");

    _ = try thread.resumeThread(null, 0);
    try expectEqual(@as(Integer, 1), try thread.toInteger(-1));
}

test "resuming" {
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
    _ = thread.getGlobal("counter");

    var i: i32 = 1;
    while (i <= 5) : (i += 1) {
        try expectEqual(ziglua.ResumeStatus.yield, try thread.resumeThread(null, 0));
        try expectEqual(@as(Integer, i), try thread.toInteger(-1));
        lua.pop(lua.getTop());
    }
    try expectEqual(ziglua.ResumeStatus.ok, try thread.resumeThread(null, 0));
    try expectEqualStrings("done", try thread.toBytes(-1));
}

test "debug interface" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\f = function(x)
        \\  local y = x * 2
        \\  y = y + 2
        \\  return x + y
        \\end
    );
    _ = lua.getGlobal("f");

    var info: DebugInfo = undefined;
    lua.getInfo(-1, .{
        .l = true,
        .s = true,
        .n = true,
        .u = true,
    }, &info);

    // get information about the function
    try expectEqual(DebugInfo.FnType.lua, info.what);
    const len = std.mem.len(@as([*:0]u8, @ptrCast(&info.short_src)));
    try expectEqualStrings("[string \"...\"]", info.short_src[0..len]);
    try expectEqual(@as(?i32, 1), info.first_line_defined);
    try expectEqual(@as(?i32, 1), info.current_line);
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
    _ = lua.getGlobal("addone");

    // index doesn't exist
    try expectError(error.Fail, lua.getUpvalue(1, 2));

    // inspect the upvalue (should be x)
    try expectEqualStrings("", try lua.getUpvalue(-1, 1));
    try expectEqual(@as(Number, 1), try lua.toNumber(-1));
    lua.pop(1);

    // now make the function an "add five" function
    lua.pushNumber(5);
    _ = try lua.setUpvalue(-2, 1);

    // call the new function (should return 7)
    lua.pushNumber(2);
    try lua.protectedCall(1, 1, 0);
    try expectEqual(@as(Number, 7), try lua.toNumber(-1));
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
            return 0;
        }
    }.inner);

    lua.pushFunction(function, "function");
    lua.protectedCall(0, 0, 0) catch {
        try expectEqualStrings("missing argument #1", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.protectedCall(1, 0, 0) catch {
        try expectEqualStrings("missing argument #2 to 'function' (number expected)", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.pushInteger(3);
    lua.protectedCall(2, 0, 0) catch {
        try expectEqualStrings("missing argument #3 to 'function' (string expected)", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushBytes("hello world");
    lua.protectedCall(3, 0, 0) catch {
        try expectEqualStrings("missing argument #4 to 'function' (number expected)", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushBytes("hello world");
    lua.pushNumber(4);
    lua.protectedCall(4, 0, 0) catch {
        try expectEqualStrings("missing argument #5 to 'function' (string expected)", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushBytes("hello world");
    lua.pushNumber(4);
    lua.pushString("hello world");
    lua.protectedCall(5, 0, 0) catch {
        try expectEqualStrings("missing argument #6 to 'function' (boolean expected)", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushBytes("hello world");
    lua.pushNumber(4);
    lua.pushString("hello world");
    lua.pushBoolean(true);
    lua.protectedCall(6, 0, 0) catch {
        try expectEqualStrings("missing argument #7 to 'function' (number expected)", try lua.toBytes(-1));
        lua.pop(-1);
    };

    lua.pushFunction(function, "function");
    lua.pushNil();
    lua.pushInteger(3);
    lua.pushBytes("hello world");
    lua.pushNumber(4);
    lua.pushString("hello world");
    lua.pushBoolean(true);
    try lua.protectedCall(6, 0, 0);
}

test "get global nil" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    _ = lua.getGlobal("foo");
    try expectEqual(LuaType.nil, lua.typeOf(-1));
}

test "metatables" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("f = function() return 10 end");

    try lua.newMetatable("mt");

    // set the len metamethod to the function f
    _ = lua.getGlobal("f");
    lua.setField(1, "__len");

    lua.newTable();
    _ = lua.getField(ziglua.registry_index, "mt");
    lua.setMetatable(-2);

    try lua.callMeta(-1, "__len");
    try expectEqual(@as(Number, 10), try lua.toNumber(-1));
}

test "aux opt functions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    const function = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            expectEqual(@as(Integer, 10), l.optInteger(1, 10)) catch unreachable;
            expectEqualStrings("zig", l.optBytes(2, "zig")) catch unreachable;
            expectEqual(@as(Number, 1.23), l.optNumber(3, 1.23)) catch unreachable;
            expectEqualStringsSentinel("lang", l.optString(4, "lang")) catch unreachable;
            return 0;
        }
    }.inner);

    lua.pushFunction(function, "function");
    try lua.protectedCall(0, 0, 0);

    lua.pushFunction(function, "function");
    lua.pushInteger(10);
    lua.pushBytes("zig");
    lua.pushNumber(1.23);
    lua.pushString("lang");
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

    lua.pushFunction(function, "function");
    lua.pushString("one");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(@as(Integer, 1), try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function, "function");
    lua.pushString("two");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(@as(Integer, 2), try lua.toInteger(-1));
    lua.pop(1);

    lua.pushFunction(function, "function");
    lua.pushString("three");
    try lua.protectedCall(1, 1, 0);
    try expectEqual(@as(Integer, 3), try lua.toInteger(-1));
    lua.pop(1);

    // try the default now
    lua.pushFunction(function, "function");
    try lua.protectedCall(0, 1, 0);
    try expectEqual(@as(Integer, 1), try lua.toInteger(-1));
    lua.pop(1);

    // check the raised error
    lua.pushFunction(function, "function");
    lua.pushString("unknown");
    try expectError(error.Runtime, lua.protectedCall(1, 1, 0));
    try expectEqualStrings("invalid argument #1 to 'function' (invalid option 'unknown')", try lua.toBytes(-1));
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

    lua.pushFunction(whereFn, "where");
    lua.setGlobal("whereFn");

    try lua.doString(
        \\
        \\ret = whereFn()
    );

    _ = lua.getGlobal("ret");
    try expectEqualStrings("[string \"...\"]:2: ", try lua.toBytes(-1));
}

test "ref" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try expectError(error.Fail, lua.ref(1));
    try expectEqual(@as(Integer, 1), lua.getTop());

    // In luau lua.ref does not pop the item from the stack
    // and the data is stored in the registry_index by default
    lua.pushBytes("Hello there");
    const ref = try lua.ref(2);

    _ = lua.rawGetIndex(ziglua.registry_index, ref);
    try expectEqualStrings("Hello there", try lua.toBytes(-1));

    lua.unref(ref);
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

    lua.pushFunction(argCheck, "argCheck");
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));

    const raisesError = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            l.raiseErrorStr("some error %s!", .{"zig"});
            unreachable;
        }
    }.inner);

    lua.pushFunction(raisesError, "raisesError");
    try expectError(error.Runtime, lua.protectedCall(0, 0, 0));
    try expectEqualStrings("some error zig!", try lua.toBytes(-1));
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
                l.pushBytes("error!");
                l.raiseError();
            }
            if (ptr.b != 3.14) {
                l.pushBytes("error!");
                l.raiseError();
            }
            return 1;
        }
    }.inner);

    lua.pushFunction(checkUdata, "checkUdata");

    {
        var t = lua.newUserdata(Type);
        try expectEqual(LuaType.table, lua.getField(ziglua.registry_index, "Type"));
        lua.setMetatable(-2);
        t.a = 1234;
        t.b = 3.14;

        // call checkUdata asserting that the udata passed in with the
        // correct metatable and values
        try lua.protectedCall(1, 1, 0);
    }
}

test "userdata slices" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.newMetatable("FixedArray");

    // create an array of 10
    const slice = lua.newUserdataSlice(Integer, 10);
    try expectEqual(LuaType.table, lua.getField(ziglua.registry_index, "FixedArray"));
    lua.setMetatable(-2);

    for (slice, 1..) |*item, index| {
        item.* = @intCast(index);
    }

    const udataFn = struct {
        fn inner(l: *Lua) i32 {
            _ = l.checkUserdataSlice(Integer, 1, "FixedArray");
            const arr = l.toUserdataSlice(Integer, 1) catch unreachable;
            for (arr, 1..) |item, index| {
                if (item != index) l.raiseErrorStr("something broke!", .{});
            }

            return 0;
        }
    }.inner;

    lua.pushFunction(ziglua.wrap(udataFn), "udataFn");
    lua.pushValue(2);

    try lua.protectedCall(1, 0, 0);
}

test "function environments" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("function test() return x end");

    // set the global _G.x to be 10
    lua.pushInteger(10);
    lua.setGlobal("x");

    _ = lua.getGlobal("test");
    try lua.protectedCall(0, 1, 0);
    try testing.expectEqual(@as(Integer, 10), try lua.toInteger(1));
    lua.pop(1);

    // now set the functions table to have a different value of x
    _ = lua.getGlobal("test");
    lua.newTable();
    lua.pushInteger(20);
    lua.setField(2, "x");
    try lua.setFnEnvironment(1);

    try lua.protectedCall(0, 1, 0);
    try testing.expectEqual(@as(Integer, 20), try lua.toInteger(1));
    lua.pop(1);

    _ = lua.getGlobal("test");
    lua.getFnEnvironment(1);
    _ = lua.getField(2, "x");
    try testing.expectEqual(@as(Integer, 20), try lua.toInteger(3));
}

test "objectLen" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushString("lua");
    try testing.expectEqual(@as(i32, 3), lua.objectLen(-1));
}

test {
    testing.refAllDecls(Lua);
    testing.refAllDecls(Buffer);
}
