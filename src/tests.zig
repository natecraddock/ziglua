//! tests.zig

const std = @import("std");
const testing = std.testing;
const ziglua = @import("ziglua.zig");

const Buffer = ziglua.Buffer;
const Error = ziglua.Error;
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
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a + b);
        return 1;
    }
}.addInner;

const sub = struct {
    fn subInner(l: *Lua) i32 {
        const a = l.toInteger(1) catch 0;
        const b = l.toInteger(2) catch 0;
        l.pushInteger(a - b);
        return 1;
    }
}.subInner;

fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
    _ = data;
    _ = osize;

    const alignment = @alignOf(std.c.max_align_t);
    if (@ptrCast(?[*]align(alignment) u8, @alignCast(alignment, ptr))) |prev_ptr| {
        const prev_slice = prev_ptr[0..osize];
        if (nsize == 0) {
            testing.allocator.free(prev_slice);
            return null;
        }
        const new_ptr = testing.allocator.reallocAdvanced(prev_slice, alignment, nsize, .exact) catch return null;
        return new_ptr.ptr;
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
    try expectError(Error.Memory, Lua.init(testing.failing_allocator));

    // use the library directly
    lua = try Lua.newState(alloc, null);
    lua.close();

    // use the library with a bad AllocFn
    try expectError(Error.Memory, Lua.newState(failing_alloc, null));

    // use the auxiliary library (uses libc realloc and cannot be checked for leaks!)
    lua = try Lua.newStateAux();
    lua.close();
}

test "alloc functions" {
    var lua = try Lua.newState(alloc, null);
    defer lua.deinit();

    // get default allocator
    var data: *anyopaque = undefined;
    try expectEqual(alloc, lua.getAllocF(&data));

    // set a bad allocator
    lua.setAllocF(failing_alloc, null);
    try expectEqual(failing_alloc, lua.getAllocF(&data));

    // reset the good one
    lua.setAllocF(alloc, null);
}

test "standard library loading" {
    // open a subset of standard libraries with Zig wrapper
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.open(.{
            .base = true,
            .coroutine = true,
            .package = true,
            .string = true,
            .utf8 = true,
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
        lua.openCoroutine();
        lua.openPackage();
        lua.openString();
        lua.openUtf8();
        lua.openTable();
        lua.openMath();
        lua.openIO();
        lua.openOS();
        lua.openDebug();
    }
}

test "arithmetic (lua_arith)" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNumber(10);
    lua.pushNumber(42);

    lua.arith(.add);
    try expectEqual(@as(f64, 52), try lua.toNumber(1));

    lua.pushNumber(12);
    lua.arith(.sub);
    try expectEqual(@as(f64, 40), try lua.toNumber(1));

    lua.pushNumber(2);
    lua.arith(.mul);
    try expectEqual(@as(f64, 80), try lua.toNumber(1));

    lua.pushNumber(8);
    lua.arith(.div);
    try expectEqual(@as(f64, 10), try lua.toNumber(1));

    // prep for idiv
    lua.pushNumber(1);
    lua.arith(.add);
    lua.pushNumber(2);
    lua.arith(.idiv);
    try expectEqual(@as(f64, 5), try lua.toNumber(1));

    lua.pushNumber(2);
    lua.arith(.mod);
    try expectEqual(@as(f64, 1), try lua.toNumber(1));

    lua.arith(.unm);
    try expectEqual(@as(f64, -1), try lua.toNumber(1));

    lua.arith(.unm);
    lua.pushNumber(2);
    lua.arith(.shl);
    try expectEqual(@as(i64, 4), try lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.shr);
    try expectEqual(@as(i64, 2), try lua.toInteger(1));

    lua.pushNumber(4);
    lua.arith(.bor);
    try expectEqual(@as(i64, 6), try lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.band);
    try expectEqual(@as(i64, 0), try lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.bxor);
    try expectEqual(@as(i64, 1), try lua.toInteger(1));

    lua.arith(.bnot); // 0xFFFFFFFFFFFFFFFE which is -2
    try expectEqual(@as(i64, -2), try lua.toInteger(1));

    lua.pushNumber(3);
    lua.arith(.pow);
    try expectEqual(@as(i64, -8), try lua.toInteger(1));
}

test "compare" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.pushNumber(1);
    lua.pushNumber(2);
    try expect(!lua.compare(-2, -1, .eq));
    try expect(!lua.compare(-1, -2, .le));
    try expect(!lua.compare(-1, -2, .lt));
    try expect(lua.compare(-2, -1, .le));
    try expect(lua.compare(-2, -1, .lt));

    try expect(!lua.rawEqual(-1, -2));
    lua.pushNumber(2);
    try expect(lua.rawEqual(-1, -2));
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
    lua.pushGlobalTable();
    lua.pushInteger(1);
    lua.pushLightUserdata(&value);
    lua.pushNil();
    lua.pushNumber(0.1);
    _ = lua.pushThread();
    _ = lua.pushString("all your codebase are belong to us");
    lua.pushFunction(ziglua.wrap(add));
    _ = lua.pushBytes("hello world");
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
}

test "typenames" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectEqualStringsSentinel("no value", lua.typeName(.none));
    try expectEqualStringsSentinel("nil", lua.typeName(.nil));
    try expectEqualStringsSentinel("boolean", lua.typeName(.boolean));
    try expectEqualStringsSentinel("userdata", lua.typeName(.light_userdata));
    try expectEqualStringsSentinel("number", lua.typeName(.number));
    try expectEqualStringsSentinel("string", lua.typeName(.string));
    try expectEqualStringsSentinel("table", lua.typeName(.table));
    try expectEqualStringsSentinel("function", lua.typeName(.function));
    try expectEqualStringsSentinel("userdata", lua.typeName(.userdata));
    try expectEqualStringsSentinel("thread", lua.typeName(.thread));
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
    lua.pop(1);
    try expectEqual(LuaType.number, lua.getGlobal("a"));
    try expectEqual(@as(i64, 12), try lua.toInteger(1));

    try expectError(Error.Syntax, lua.loadString("bad syntax"));
    try lua.loadString("a = g()");
    try expectError(Error.Runtime, lua.protectedCall(0, 0, 0));
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
    try expectError(Error.Fail, lua.checkStack(1_000_000));

    // this is small enough it won't fail (would raise an error if it did)
    lua.checkStackAux(40, null);
    while (count < 40) : (count += 1) {
        lua.pushNil();
    }

    try expectEqual(@as(i32, 40), lua.getTop());
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
    try expectEqual(@as(i32, 10), lua.getTop());

    lua.copy(1, 2);
    try expectEqual(@as(i64, 10), try lua.toInteger(1));
    try expectEqual(@as(i64, 10), try lua.toInteger(2));
    try expectEqual(@as(i64, 1), try lua.toInteger(3));
    try expectEqual(@as(i64, 8), try lua.toInteger(-1));

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

test "version" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try expectEqual(@as(f64, 504), lua.version());
}

test "string buffers" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var buffer: Buffer = undefined;
    buffer.init(lua);
    try expectEqual(@as(usize, 0), buffer.len());

    buffer.addChar('z');
    buffer.addChar('i');
    buffer.addChar('g');
    buffer.addString("lua");
    try expectEqual(@as(usize, 6), buffer.len());

    buffer.sub(3);
    try expectEqual(@as(usize, 3), buffer.len());

    var str = buffer.prepSize(3);
    str[0] = 'l';
    str[1] = 'u';
    str[2] = 'a';
    try expectEqual(@as(usize, 3), buffer.len());
    buffer.addSize(3);
    try expectEqual(@as(usize, 6), buffer.len());
    try expectEqualStrings("ziglua", buffer.addr());

    buffer.addLString(" api ");
    try expectEqualStrings("ziglua api ", buffer.addr());

    lua.pushNumber(5.4);
    buffer.addValue();
    try expectEqual(@as(usize, 14), buffer.len());
    try expectEqualStrings("ziglua api 5.4", buffer.addr());

    buffer.sub(4);
    try expectEqualStrings("ziglua api", buffer.addr());

    buffer.addGSub(" some string here", "string", "text");
    try expectEqualStrings("ziglua api some text here", buffer.addr());

    buffer.pushResult();
    try expectEqualStrings("ziglua api some text here", try lua.toBytes(-1));

    // now test a small buffer
    buffer = undefined;
    var b = buffer.initSize(lua, 3);
    b[0] = 'a';
    b[1] = 'b';
    b[2] = 'c';
    buffer.addSize(3);
    b = buffer.prep();
    std.mem.copy(u8, b, "defghijklmnopqrstuvwxyz");
    buffer.pushResultSize(23);
    try expectEqualStrings("abcdefghijklmnopqrstuvwxyz", try lua.toBytes(-1));

    lua.len(-1);
    try expectEqual(@as(Integer, 26), try lua.toInteger(-1));
}

test "global table" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // open some libs so we can inspect them
    lua.open(.{ .math = true, .base = true });
    lua.pushGlobalTable();

    // find the print function
    _ = lua.pushString("print");
    try expectEqual(LuaType.function, lua.getTable(-2));

    // index the global table in the global table
    try expectEqual(LuaType.table, lua.getField(-2, "_G"));

    // find pi in the math table
    try expectEqual(LuaType.table, lua.getField(-1, "math"));
    try expectEqual(LuaType.number, lua.getField(-1, "pi"));

    // but the string table should be nil
    lua.pop(2);
    try expectEqual(LuaType.nil, lua.getField(-1, "string"));
}

test "function registration" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // register all functions as part of a table
    const funcs = [_]ziglua.FnReg{
        .{ .name = "add", .func = ziglua.wrap(add) },
        .{ .name = "sub", .func = ziglua.wrap(sub) },
        .{ .name = "placeholder", .func = null },
    };
    lua.newTable();
    lua.setFuncs(&funcs, 0);

    try expectEqual(LuaType.boolean, lua.getField(-1, "placeholder"));
    lua.pop(1);
    try expectEqual(LuaType.function, lua.getField(-1, "add"));
    lua.pop(1);
    try expectEqual(LuaType.function, lua.getField(-1, "sub"));

    // also try calling the sub function sub(42, 40)
    lua.pushInteger(42);
    lua.pushInteger(40);
    try lua.protectedCall(2, 1, 0);
    try expectEqual(@as(Integer, 2), try lua.toInteger(-1));

    // now test the newlib variation to build a library from functions
    // indirectly tests newLibTable
    lua.newLib(&funcs);
    // add functions to the global table under "funcs"
    lua.setGlobal("funcs");

    try lua.doString("funcs.add(10, 20)");
    try lua.doString("funcs.sub('10', 20)");
    try expectError(Error.Runtime, lua.doString("funcs.placeholder()"));
}

test "panic fn" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // just test setting up the panic function
    // it uses longjmp so cannot return here to test
    // TODO: perhaps a later version of zig can test an expected fail
    const panicFn = ziglua.wrap(struct {
        fn inner(l: *Lua) i32 {
            _ = l;
            return 0;
        }
    }.inner);
    try expectEqual(@as(?ziglua.CFn, null), lua.atPanic(panicFn));
}

test "warn fn" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.warning("this message is going to the void", false);

    const warnFn = ziglua.wrap(struct {
        fn inner(data: ?*anyopaque, msg: []const u8, to_cont: bool) void {
            _ = data;
            _ = to_cont;
            if (!std.mem.eql(u8, msg, "this will be caught by the warnFn")) panic("test failed", .{});
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

    try expectEqualStrings("hello 10.0 wow!", try lua.toBytes(-1));
}

test "garbage collector" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // because the garbage collector is an opaque, unmanaged
    // thing, it is hard to test, so just run each function
    lua.gc(.stop, .{});
    lua.gc(.collect, .{});
    lua.gc(.restart, .{});
    lua.gc(.step, .{10});
    _ = lua.gc(.count, .{});
    _ = lua.gc(.countb, .{});
    _ = lua.gc(.is_running, .{});
    try expect(lua.gc(.set_generational, .{ 0, 10 }));
    try expect(lua.gc(.set_incremental, .{ 0, 0, 0 }));
    try expect(!lua.gc(.set_incremental, .{ 0, 0, 0 }));
}

test "extra space" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var space = @ptrCast(*align(1) usize, lua.getExtraSpace().ptr);
    space.* = 1024;
    // each new thread is initialized with a copy of the extra space from the main thread
    var thread = lua.newThread();
    try expectEqual(@as(usize, 1024), @ptrCast(*align(1) usize, thread.getExtraSpace()).*);
}

test "table access" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try lua.doString("a = { [1] = 'first', key = 'value', ['other one'] = 1234 }");
    _ = lua.getGlobal("a");

    try expectEqual(LuaType.string, lua.getIndex(1, 1));
    try expectEqualStrings("first", try lua.toBytes(-1));

    try expectEqual(LuaType.string, lua.rawGetIndex(1, 1));
    try expectEqualStrings("first", try lua.toBytes(-1));

    _ = lua.pushString("key");
    try expectEqual(LuaType.string, lua.getTable(1));
    try expectEqualStrings("value", try lua.toBytes(-1));

    _ = lua.pushString("other one");
    try expectEqual(LuaType.number, lua.rawGetTable(1));
    try expectEqual(@as(Integer, 1234), try lua.toInteger(-1));

    // a.name = "ziglua"
    _ = lua.pushString("name");
    _ = lua.pushString("ziglua");
    lua.setTable(1);

    // a.lang = "zig"
    _ = lua.pushString("lang");
    _ = lua.pushString("zig");
    lua.rawSetTable(1);

    try expectError(Error.Fail, lua.getMetatable(1));

    // create a metatable (it isn't a useful one)
    lua.newTable();
    lua.pushFunction(ziglua.wrap(add));
    lua.setField(-2, "__len");
    lua.setMetatable(1);

    try lua.getMetatable(1);
    _ = try lua.getMetaField(1, "__len");
    try expectError(Error.Fail, lua.getMetaField(1, "__index"));

    lua.pushBoolean(true);
    lua.setField(1, "bool");

    try lua.doString("b = a.bool");
    try expectEqual(LuaType.boolean, lua.getGlobal("b"));
    try expect(lua.toBoolean(-1));

    // create array [1, 2, 3, 4, 5]
    lua.createTable(0, 0);
    var index: Integer = 1;
    while (index <= 5) : (index += 1) {
        lua.pushInteger(index);
        lua.setIndex(-2, index);
    }
    try expectEqual(@as(ziglua.Unsigned, 5), lua.rawLen(-1));
    try expectEqual(@as(Integer, 5), lua.lenAux(-1));

    // add a few more
    while (index <= 10) : (index += 1) {
        lua.pushInteger(index);
        lua.rawSetIndex(-2, index);
    }
    try expectEqual(@as(ziglua.Unsigned, 10), lua.rawLen(-1));
}

test "conversions" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // number conversion
    var value: Integer = undefined;
    try Lua.numberToInteger(3.14, &value);
    try expectEqual(@as(Integer, 3), value);
    try expectError(Error.Fail, Lua.numberToInteger(@intToFloat(Number, ziglua.max_integer) + 10, &value));

    // string conversion
    try lua.stringToNumber("1");
    try expect(lua.isInteger(-1));
    try expectEqual(@as(Integer, 1), try lua.toInteger(1));

    try lua.stringToNumber("  1.0  ");
    try expect(lua.isNumber(-1));
    try expectEqual(@as(Number, 1.0), try lua.toNumber(-1));

    try expectError(Error.Fail, lua.stringToNumber("a"));
    try expectError(Error.Fail, lua.stringToNumber("1.a"));
    try expectError(Error.Fail, lua.stringToNumber(""));

    // index conversion
    try expectEqual(@as(i32, 2), lua.absIndex(-1));
    try expectEqual(@as(i32, 1), lua.absIndex(-2));
}

test "dump and load" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // store a function in a global
    try lua.doString("f = function(x) return function(n) return n + x end end");
    // put the function on the stack
    _ = lua.getGlobal("f");

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
    try lua.dump(ziglua.wrap(writer), &buffer, false);

    // clear the stack
    try lua.resetThread();

    const reader = struct {
        fn inner(l: *Lua, data: *anyopaque) ?[]const u8 {
            _ = l;
            var arr = ziglua.opaqueCast(std.ArrayList(u8), data);
            return arr.items;
        }
    }.inner;

    // now load the function back onto the stack
    try lua.load(ziglua.wrap(reader), &buffer, "function", .binary);
    try expectEqual(LuaType.function, lua.typeOf(-1));

    // run the function (creating a new function)
    lua.pushInteger(5);
    try lua.protectedCall(1, 1, 0);

    // now call the new function (which should return the value + 5)
    lua.pushInteger(6);
    try lua.protectedCall(1, 1, 0);
    try expectEqual(@as(Integer, 11), try lua.toInteger(-1));
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

    // create a Lua-owned pointer to a Data with 2 associated user values
    var data = lua.newUserdataUV(Data, 2);
    data.val = 1;
    std.mem.copy(u8, &data.code, "abcd");

    // assign the user values
    lua.pushNumber(1234.56);
    try lua.setIndexUserValue(1, 1);

    _ = lua.pushString("test string");
    try lua.setIndexUserValue(1, 2);

    try expectEqual(LuaType.number, try lua.getIndexUserValue(1, 1));
    try expectEqual(@as(Number, 1234.56), try lua.toNumber(-1));
    try expectEqual(LuaType.string, try lua.getIndexUserValue(1, 2));
    try expectEqualStrings("test string", try lua.toBytes(-1));

    try expectError(Error.Fail, lua.setIndexUserValue(1, 3));
    try expectError(Error.Fail, lua.getIndexUserValue(1, 3));

    try expectEqual(data, ziglua.opaqueCast(Data, try lua.toUserdata(1)));
    try expectEqual(@ptrCast(*const anyopaque, data), @alignCast(@alignOf(Data), try lua.toPointer(1)));
}

test "upvalues" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // counter from PIL
    const counter = struct {
        fn inner(l: *Lua) i32 {
            var counter = l.toInteger(Lua.upvalueIndex(1)) catch 0;
            counter += 1;
            l.pushInteger(counter);
            l.copy(-1, Lua.upvalueIndex(1));
            return 1;
        }
    }.inner;

    // Initialize the counter at 0
    lua.pushInteger(0);
    lua.pushClosure(ziglua.wrap(counter), 1);
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

test "registry" {
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
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    lua.open(.{ .base = true });

    // do setup in Lua for ease
    try lua.doString(
        \\closed_vars = 0
        \\mt = { __close = function() closed_vars = closed_vars + 1 end }
    );

    lua.newTable();
    _ = lua.getGlobal("mt");
    lua.setMetatable(-2);
    lua.toClose(-1);
    lua.closeSlot(-1);
    lua.pop(1);

    lua.newTable();
    _ = lua.getGlobal("mt");
    lua.setMetatable(-2);
    lua.toClose(-1);
    lua.closeSlot(-1);
    lua.pop(1);

    // this should have incremented "closed_vars" to 2
    _ = lua.getGlobal("closed_vars");
    try expectEqual(@as(Number, 2), try lua.toNumber(-1));
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

    lua.pushFunction(ziglua.wrap(makeError));
    try expectError(Error.Runtime, lua.protectedCall(0, 0, 0));
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
    try expect(thread.isYieldable());

    var results: i32 = undefined;
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        try expectEqual(ziglua.ResumeStatus.yield, try thread.resumeThread(lua, 0, &results));
        try expectEqual(@as(Integer, i), try thread.toInteger(-1));
        thread.pop(results);
    }
    try expectEqual(ziglua.ResumeStatus.ok, try thread.resumeThread(lua, 0, &results));
    try expectEqualStrings("done", try thread.toBytes(-1));
}

test "refs" {
    // temporary test that includes a reference to all functions so
    // they will be type-checked

    // debug
    _ = Lua.getHook;
    _ = Lua.getHookCount;
    _ = Lua.getHookMask;
    _ = Lua.getInfo;
    _ = Lua.getLocal;
    _ = Lua.getStack;
    _ = Lua.getUpvalue;
    _ = Lua.setHook;
    _ = Lua.setLocal;
    _ = Lua.setUpvalue;
    _ = Lua.upvalueId;
    _ = Lua.upvalueJoin;

    // auxlib
    _ = Lua.argCheck;
    _ = Lua.argError;
    _ = Lua.argExpected;
    _ = Lua.callMeta;
    _ = Lua.checkAny;
    _ = Lua.checkInteger;
    _ = Lua.checkLString;
    _ = Lua.checkNumber;
    _ = Lua.checkOption;
    _ = Lua.checkString;
    _ = Lua.checkType;
    _ = Lua.checkUserdata;
    _ = Lua.checkVersion;
    _ = Lua.doFile;
    _ = Lua.raiseErrorAux;
    _ = Lua.exeResult;
    _ = Lua.fileResult;
    _ = Lua.getMetatableAux;
    _ = Lua.getSubtable;
    _ = Lua.gSub;
    _ = Lua.loadBuffer;
    _ = Lua.loadBufferX;
    _ = Lua.loadFile;
    _ = Lua.loadFileX;
    _ = Lua.newMetatable;
    _ = Lua.optInteger;
    _ = Lua.optLString;
    _ = Lua.optNumber;
    _ = Lua.optString;
    _ = Lua.pushFail;
    _ = Lua.requireF;
    _ = Lua.setMetatableAux;
    _ = Lua.testUserdata;
    _ = Lua.toLStringAux;
    _ = Lua.traceback;
    _ = Lua.typeError;
    _ = Lua.typeNameAux;
    _ = Lua.unref;
    _ = Lua.where;
}
