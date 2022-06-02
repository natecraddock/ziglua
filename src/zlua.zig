//! zlua.zig

const std = @import("std");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

const Allocator = std.mem.Allocator;

/// A Zig wrapper around the Lua C API
const Lua = struct {
    allocator: ?*Allocator = null,
    state: *c.lua_State,

    /// Allows Lua to allocate memory using a Zig allocator passed in via data.
    /// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
    fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
        _ = osize; // unused

        // just like malloc() returns a pointer "which is suitably aligned for any built-in type",
        // the memory allocated by this function should also be aligned for any type that Lua may
        // desire to allocate. use the largest alignment for the target
        const alignment = @alignOf(std.c.max_align_t);

        // the data pointer is an Allocator, so the @alignCast is safe
        const allocator = @ptrCast(*Allocator, @alignCast(@alignOf(Allocator), data));

        if (@ptrCast(?[*]align(alignment) u8, @alignCast(alignment, ptr))) |prev_ptr| {
            const prev_slice = prev_ptr[0..osize];

            // when nsize is zero the allocator must behave like free and return null
            if (nsize == 0) {
                allocator.free(prev_slice);
                return null;
            }

            // when nsize is not zero the allocator must behave like realloc
            const new_ptr = allocator.reallocAdvanced(prev_slice, alignment, nsize, .exact) catch return null;
            return new_ptr.ptr;
        } else {
            // ptr is null, allocate a new block of memory
            const new_ptr = allocator.alignedAlloc(u8, alignment, nsize) catch return null;
            return new_ptr.ptr;
        }
    }

    /// Initialize a Lua state with the given allocator
    pub fn init(allocator: Allocator) !Lua {
        // the userdata passed to alloc needs to be a pointer with a consistent address
        // so we allocate an Allocator struct to hold a copy of the allocator's data
        var allocator_ptr = try allocator.create(Allocator);
        allocator_ptr.* = allocator;

        const state = c.lua_newstate(alloc, allocator_ptr) orelse return error.OutOfMemory;
        return Lua{
            .allocator = allocator_ptr,
            .state = state,
        };
    }

    /// Deinitialize a Lua state and free all memory
    pub fn deinit(lua: *Lua) void {
        lua.close();
        if (lua.allocator) |a| {
            const allocator = a;
            allocator.destroy(a);
            lua.allocator = null;
        }
    }

    // Library functions
    //
    // Library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// The type of function that Lua uses for all internal allocations and frees
    /// `data` is an opaque pointer to any data (the allocator), `ptr` is a pointer to the block being alloced/realloced/freed
    /// `osize` is the original size or a code, and `nsize` is the new size
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
    pub const AllocFn = fn (data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque;

    /// Converts the acceptable index `index` into an equivalent absolute index
    pub fn absIndex(lua: *Lua, index: i32) i32 {
        return c.lua_absindex(lua.state, index);
    }

    /// Operations supported by `Lua.arith()`
    pub const Operator = enum(u4) {
        add = c.LUA_OPADD,
        sub = c.LUA_OPSUB,
        mul = c.LUA_OPMUL,
        div = c.LUA_OPDIV,
        idiv = c.LUA_OPIDIV,
        mod = c.LUA_OPMOD,
        pow = c.LUA_OPPOW,
        unm = c.LUA_OPUNM,
        bnot = c.LUA_OPBNOT,
        band = c.LUA_OPBAND,
        bor = c.LUA_OPBOR,
        bxor = c.LUA_OPBXOR,
        shl = c.LUA_OPSHL,
        shr = c.LUA_OPSHR,
    };

    /// Performs an arithmetic or bitwise operation over the value(s) at the top of the stack
    /// This function follows the semantics of the corresponding Lua operator
    pub fn arith(lua: *Lua, op: Operator) void {
        c.lua_arith(lua.state, @enumToInt(op));
    }

    /// Release all Lua objects in the state and free all dynamic memory
    pub fn close(lua: *Lua) void {
        c.lua_close(lua.state);
    }

    /// Creates a new independent state and returns its main thread
    pub fn newState(alloc_fn: AllocFn, data: ?*anyopaque) !Lua {
        const state = c.lua_newstate(alloc_fn, data) orelse return error.OutOfMemory;
        return Lua{ .state = state };
    }

    /// Pops `n` elements from the top of the stack
    pub fn pop(lua: *Lua, n: i32) void {
        lua.setTop(-n - 1);
    }

    /// Pushes a boolean value with value `b` onto the stack
    pub fn pushBoolean(lua: *Lua, b: bool) void {
        c.lua_pushboolean(lua.state, @boolToInt(b));
    }

    /// Type for C functions
    /// See https://www.lua.org/manual/5.4/manual.html#lua_CFunction for the protocol
    const CFunction = fn (state: c.lua_State) callconv(.C) c_int;

    /// Pushes a new C Closure onto the stack
    /// `n` tells how many upvalues this function will have
    /// TODO: add a Zig interface to pass Zig functions wrapped
    pub fn pushCClosure(lua: *Lua, c_fn: CFunction, n: i32) void {
        _ = lua;
        _ = c_fn;
        _ = n;
    }

    /// Pushes a C function onto the stack.
    /// Equivalent to pushCClosure with no upvalues
    pub fn pushCFunction(lua: *Lua, c_fn: CFunction) void {
        lua.pushCClosure(c_fn, 0);
    }

    /// Push a formatted string onto the stack and return a pointer to the string
    /// TODO: check if this works...
    pub fn pushFString(lua: *Lua, fmt: []const u8, args: anytype) [*]const u8 {
        const ptr = @call(.{}, c.lua_pushfstring, .{ lua.state, fmt } ++ args);
        return @ptrCast([*]const u8, ptr);
    }

    /// Pushes the global environment onto the stack
    pub fn pushGlobalTable(lua: *Lua) void {
        c.lua_pushglobaltable(lua.state);
    }

    /// Pushes an integer with value `n` onto the stack
    pub fn pushInteger(lua: *Lua, n: i32) void {
        c.lua_pushinteger(lua.state, n);
    }

    /// Pushes a light userdata onto the stack
    pub fn pushLightUserdata(lua: *Lua, ptr: *anyopaque) void {
        c.lua_pushlightuserdata(lua.state, ptr);
    }

    pub fn pushLiteral(lua: *Lua, str: []const u8) []const u8 {
        c.lua_pushliteral(lua.state, str); // TODO
    }

    pub fn pushLString(lua: *Lua, str: []const u8, len: usize) []const u8 {
        _ = lua;
        _ = str;
        _ = len;
    }

    /// Pushes a nil value onto the stack
    pub fn pushNil(lua: *Lua) void {
        c.lua_pushnil(lua.state);
    }

    /// Pushes a float with value `n` onto the stack
    pub fn pushNumber(lua: *Lua, n: f64) void {
        c.lua_pushnumber(lua.state, n);
    }

    /// Pushes a zero-terminated string onto the stack
    /// Lua makes a copy of the string so `str` may be freed immediately after return
    /// Returns a pointer to the internal Lua string
    /// If `str` is null pushes nil and returns null
    pub fn pushString(lua: *Lua, str: ?[:0]const u8) ?[*]const u8 {
        const ptr = c.lua_pushstring(lua.state, str);
        return @ptrCast(?[*]const u8, ptr);
    }

    /// Pushes this thread onto the stack
    /// Returns true if this thread is the main thread of its state
    pub fn pushThread(lua: *Lua) bool {
        return c.lua_pushthread(lua.state) == 1;
    }

    /// Pushes a copy of the element at the given index onto the stack
    pub fn pushValue(lua: *Lua, index: i32) void {
        c.lua_pushvalue(lua.state, index);
    }

    // TODO: pub fn pushVFString is that even worth?

    /// Sets the top of the stack to `index`
    /// If the new top is greater than the old, new elements are filled with nil
    /// If `index` is 0 all stack elements are removed
    pub fn setTop(lua: *Lua, index: i32) void {
        c.lua_settop(lua.state, index);
    }

    /// Equivalent to toIntegerX with is_num set to null
    pub fn toInteger(lua: *Lua, index: i32) i64 {
        return lua.toIntegerX(index, null);
    }

    /// Converts the Lua value at the given index to a signed integer
    /// The Lua value must be an integer, or a number, or a string convertible to an integer otherwise toIntegerX returns 0
    /// If `is_num` is not null, it's referent is assigned a boolean success value
    pub fn toIntegerX(lua: *Lua, index: i32, is_num: ?*bool) i64 {
        if (is_num) |is_num_ptr| {
            var success: c_int = undefined;
            const result = c.lua_tointegerx(lua.state, index, &success);
            is_num_ptr.* = success != 0;
            return result;
        } else return c.lua_tointegerx(lua.state, index, null);
    }

    /// Equivalent to toNumberX with is_num set to null
    pub fn toNumber(lua: *Lua, index: i32) f64 {
        return lua.toNumberX(index, null);
    }

    /// Converts the Lua value at the given index to a float
    /// The Lua value must be a number or a string convertible to a number otherwise toNumberX returns 0
    /// If `is_num` is not null, it's referent is assigned a boolean success value
    pub fn toNumberX(lua: *Lua, index: i32, is_num: ?*bool) f64 {
        if (is_num) |is_num_ptr| {
            var success: c_int = undefined;
            const result = c.lua_tonumberx(lua.state, index, &success);
            is_num_ptr.* = success != 0;
            return result;
        } else return c.lua_tonumberx(lua.state, index, null);
    }

    // Auxiliary library functions

    /// Creates a new Lua state with an allocator using the default libc allocator
    pub fn auxNewState() !Lua {
        const state = c.luaL_newstate() orelse return error.OutOfMemory;
        return Lua{ .state = state };
    }

    // Standard library loading functions
    // TODO: opening libs can run arbitrary Lua code and can throw any error

    pub const Libs = packed struct {
        base: bool = false,
        coroutine: bool = false,
        package: bool = false,
        string: bool = false,
        utf8: bool = false,
        table: bool = false,
        math: bool = false,
        io: bool = false,
        os: bool = false,
        debug: bool = false,
    };

    /// Opens the specified standard library functions
    pub fn open(lua: *Lua, libs: Libs) void {
        if (libs.base) lua.openBase();
        if (libs.coroutine) lua.openCoroutine();
        if (libs.package) lua.openPackage();
        if (libs.string) lua.openString();
        if (libs.utf8) lua.openUtf8();
        if (libs.table) lua.openTable();
        if (libs.math) lua.openMath();
        if (libs.io) lua.openIO();
        if (libs.os) lua.openOS();
        if (libs.debug) lua.openDebug();
    }

    /// Open all standard libraries
    pub fn auxOpenLibs(lua: *Lua) void {
        c.luaL_openlibs(lua.state);
    }

    /// Open the basic standard library
    pub fn openBase(lua: *Lua) void {
        _ = c.luaopen_base(lua.state);
    }

    /// Open the coroutine standard library
    pub fn openCoroutine(lua: *Lua) void {
        _ = c.luaopen_coroutine(lua.state);
    }

    /// Open the package standard library
    pub fn openPackage(lua: *Lua) void {
        _ = c.luaopen_package(lua.state);
    }

    /// Open the string standard library
    pub fn openString(lua: *Lua) void {
        _ = c.luaopen_string(lua.state);
    }

    /// Open the UTF-8 standard library
    pub fn openUtf8(lua: *Lua) void {
        _ = c.luaopen_utf8(lua.state);
    }

    /// Open the table standard library
    pub fn openTable(lua: *Lua) void {
        _ = c.luaopen_table(lua.state);
    }

    /// Open the math standard library
    pub fn openMath(lua: *Lua) void {
        _ = c.luaopen_math(lua.state);
    }

    /// Open the io standard library
    pub fn openIO(lua: *Lua) void {
        _ = c.luaopen_io(lua.state);
    }

    /// Open the os standard library
    pub fn openOS(lua: *Lua) void {
        _ = c.luaopen_os(lua.state);
    }

    /// Open the debug standard library
    pub fn openDebug(lua: *Lua) void {
        _ = c.luaopen_debug(lua.state);
    }
};

// Tests

const testing = std.testing;
const expectEqual = testing.expectEqual;

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
    lua.deinit();

    // attempt to initialize the Zig wrapper with no memory
    try testing.expectError(error.OutOfMemory, Lua.init(testing.failing_allocator));

    // use the library directly
    var allocator = testing.allocator_instance.allocator();
    lua = try Lua.newState(Lua.alloc, &allocator);
    lua.close();

    // use the library with a bad AllocFn
    try testing.expectError(error.OutOfMemory, Lua.newState(failing_alloc, null));

    // use the auxiliary library
    lua = try Lua.auxNewState();
    lua.close();
}

test "standard library loading" {
    // open a subset of standard libraries with Zig wrapper
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.open(.{ .base = true, .utf8 = true, .string = true });
    }

    // open all standard libraries
    {
        var lua = try Lua.init(testing.allocator);
        defer lua.deinit();
        lua.auxOpenLibs();
    }

    // open all standard libraries with individual functions
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
    try expectEqual(@as(f64, 52), lua.toNumber(1));

    lua.pushNumber(12);
    lua.arith(.sub);
    try expectEqual(@as(f64, 40), lua.toNumber(1));

    lua.pushNumber(2);
    lua.arith(.mul);
    try expectEqual(@as(f64, 80), lua.toNumber(1));

    lua.pushNumber(8);
    lua.arith(.div);
    try expectEqual(@as(f64, 10), lua.toNumber(1));

    // prep for idiv
    lua.pushNumber(1);
    lua.arith(.add);
    lua.pushNumber(2);
    lua.arith(.idiv);
    try expectEqual(@as(f64, 5), lua.toNumber(1));

    lua.pushNumber(2);
    lua.arith(.mod);
    try expectEqual(@as(f64, 1), lua.toNumber(1));

    lua.arith(.unm);
    try expectEqual(@as(f64, -1), lua.toNumber(1));

    lua.arith(.unm);
    lua.pushNumber(2);
    lua.arith(.shl);
    try expectEqual(@as(i64, 4), lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.shr);
    try expectEqual(@as(i64, 2), lua.toInteger(1));

    lua.pushNumber(4);
    lua.arith(.bor);
    try expectEqual(@as(i64, 6), lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.band);
    try expectEqual(@as(i64, 0), lua.toInteger(1));

    lua.pushNumber(1);
    lua.arith(.bxor);
    try expectEqual(@as(i64, 1), lua.toInteger(1));

    lua.arith(.bnot); // 0xFFFFFFFFFFFFFFFE which is -2
    try expectEqual(@as(i64, -2), lua.toInteger(1));

    lua.pushNumber(3);
    lua.arith(.pow);
    try expectEqual(@as(i64, -8), lua.toInteger(1));
}
