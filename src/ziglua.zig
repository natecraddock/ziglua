//! ziglua.zig

const std = @import("std");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

const Allocator = std.mem.Allocator;

/// A Zig wrapper around the Lua C API
pub const Lua = struct {
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

    // Types
    //
    // Lua constants and types are declared below in alphabetical order
    // For constants that have a logical grouping (like Operators), Zig enums are used for type safety

    /// The type of function that Lua uses for all internal allocations and frees
    /// `data` is an opaque pointer to any data (the allocator), `ptr` is a pointer to the block being alloced/realloced/freed
    /// `osize` is the original size or a code, and `nsize` is the new size
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
    pub const AllocFunction = fn (data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque;

    /// Operations supported by `Lua.arith()`
    pub const ArithOperator = enum(u4) {
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

    /// Type for C functions
    /// See https://www.lua.org/manual/5.4/manual.html#lua_CFunction for the protocol
    pub const CFunction = fn (state: *c.lua_State) callconv(.C) c_int;

    /// Operations supported by `Lua.compare()`
    pub const CompareOperator = enum(u2) {
        eq = c.LUA_OPEQ,
        lt = c.LUA_OPLT,
        le = c.LUA_OPLE,
    };

    /// Actions supported by `Lua.gc()`
    pub const GCAction = enum(u5) {
        stop = c.LUA_GCSTOP,
        restart = c.LUA_GCRESTART,
        collect = c.LUA_GCCOLLECT,
        count = c.LUA_GCCOUNT,
        countb = c.LUA_GCCOUNTB,
        step = c.LUA_GCSTEP,
        is_running = c.LUA_GCISRUNNING,
        inc = c.LUA_GCINC,
        gen = c.LUA_GCGEN,
    };

    /// Type of integers in Lua (typically an i64)
    pub const Integer = c.lua_Integer;

    /// Type for continuation-function contexts (usually isize)
    pub const KContext = isize;

    pub const KFunction = fn (state: *c.lua_State, status: c_int, ctx: KContext) callconv(.C) c_int;

    /// Bitflag for the Lua standard libraries
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

    /// Lua types
    /// Must be a signed integer because LuaType.none is -1
    pub const LuaType = enum(i5) {
        none = c.LUA_TNONE,
        nil = c.LUA_TNIL,
        boolean = c.LUA_TBOOLEAN,
        light_userdata = c.LUA_TLIGHTUSERDATA,
        number = c.LUA_TNUMBER,
        string = c.LUA_TSTRING,
        table = c.LUA_TTABLE,
        function = c.LUA_TFUNCTION,
        userdata = c.LUA_TUSERDATA,
        thread = c.LUA_TTHREAD,
    };

    /// Type of floats in Lua (typically an f64)
    pub const Number = c.lua_Number;

    /// Index of the regsitry in the stack (pseudo-index)
    pub const registry_index = c.LUA_REGISTRYINDEX;

    /// Index of globals in the registry
    pub const ridx_globals = c.LUA_RIDX_GLOBALS;

    /// The type of the writer function used by `Lua.dump()`
    pub const Writer = fn (state: *c.lua_State, buf: *anyopaque, size: usize, data: *anyopaque) callconv(.C) c_int;

    // Library functions
    //
    // Library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Converts the acceptable index `index` into an equivalent absolute index
    pub fn absIndex(lua: *Lua, index: i32) i32 {
        return c.lua_absindex(lua.state, index);
    }

    /// Performs an arithmetic or bitwise operation over the value(s) at the top of the stack
    /// This function follows the semantics of the corresponding Lua operator
    pub fn arith(lua: *Lua, op: ArithOperator) void {
        c.lua_arith(lua.state, @enumToInt(op));
    }

    /// Sets a new panic function and returns the old one
    pub fn atPanic(lua: *Lua, panic_fn: CFunction) ?CFunction {
        return c.lua_atpanic(lua.state, panic_fn);
    }

    /// Calls a function (or any callable value)
    pub fn call(lua: *Lua, num_args: i32, num_results: i32) void {
        c.lua_call(lua.state, num_args, num_results);
    }

    /// Like `call`, but allows the called function to yield
    pub fn callK(lua: *Lua, num_args: i32, num_results: i32, ctx: KContext, k: KFunction) void {
        c.lua_call(lua.state, num_args, num_results, ctx, k);
    }

    /// Ensures that the stack has space for at least `n` extra arguments
    /// Returns false if it cannot fulfil the request
    /// Never shrinks the stack
    pub fn checkStack(lua: *Lua, n: i32) bool {
        return c.lua_checkstack(lua.state, n) != 0;
    }

    /// Release all Lua objects in the state and free all dynamic memory
    pub fn close(lua: *Lua) void {
        c.lua_close(lua.state);
    }

    /// Close the to-be-closed slot at the given `index` and set the value to nil
    pub fn closeSlot(lua: *Lua, index: i32) void {
        c.lua_closeslot(lua.state, index);
    }

    /// Compares two Lua values
    /// Returns true if the value at `index1` satisfies `op` when compared with the value at `index2`
    /// Returns false otherwise, or if any index is not valid
    pub fn compare(lua: *Lua, index1: i32, index2: i32, op: CompareOperator) bool {
        // TODO: perhaps support gt/ge by swapping args...
        return c.lua_compare(lua.state, index1, index2, @enumToInt(op)) != 0;
    }

    /// Concatenates the `n` values at the top of the stack, pops them, and leaves the result at the top
    /// If `n` is 1, the result is a single value on the stack (nothing changes)
    /// If `n` is 0, the result is the empty string
    pub fn concat(lua: *Lua, n: i32) void {
        c.lua_concat(lua.state, n);
    }

    /// Copies the element at `from_index` to the valid index `to_index`, replacing the value at that position
    pub fn copy(lua: *Lua, from_index: i32, to_index: i32) void {
        c.lua_copy(lua.state, from_index, to_index);
    }

    /// Creates a new empty table and pushes onto the stack
    /// `num_arr` is a hint for how many elements the table will have as a sequence
    /// `num_rec` is a hint for how many other elements the table will have
    /// Lua may preallocate memory for the table based on the hints
    pub fn createTable(lua: *Lua, num_arr: i32, num_rec: i32) void {
        c.lua_createtable(lua.state, num_arr, num_rec);
    }

    /// Dumps a function as a binary chunk
    pub fn dump(lua: *Lua, writer: Writer, data: *anyopaque, strip: bool) i32 {
        return c.lua_dump(lua.state, writer, data, strip);
    }

    /// Raises a Lua error using the value at the top of the stack as the error object
    /// Does a longjump and therefore never returns
    pub fn luaError(lua: *Lua) noreturn {
        c.lua_error(lua.state);
    }

    /// Controls the garbage collector
    pub fn gc(lua: *Lua, action: GCAction, args: anytype) bool {
        return @call(.{}, c.lua_gc, .{ lua.state, @enumToInt(action) } ++ args) != 0;
    }

    /// Returns the memory allocation function of a given state
    /// If `data` is not null, it is set to the opaque pointer given when the allocator function was set
    pub fn getAllocF(lua: *Lua, data: ?*?*anyopaque) AllocFunction {
        return c.lua_getallocf(lua.state, data);
    }

    /// Pushes onto the stack the value t[key] where t is the value at the given `index`
    pub fn getField(lua: *Lua, index: i32, key: [:0]const u8) LuaType {
        return @intToEnum(LuaType, c.lua_getfield(lua.state, index, key));
    }

    /// Returns a pointer to a raw memory area associated with the given Lua state
    /// The application may use this area for any purpose; Lua does not use it for anything
    pub fn getExtraSpace(lua: *Lua) *anyopaque {
        return c.lua_getextraspace(lua.state);
    }

    /// Pushes onto the stack the value of the global `name`. Returns the type of that value
    pub fn getGlobal(lua: *Lua, name: [:0]const u8) LuaType {
        return @intToEnum(LuaType, c.lua_getglobal(lua.state, name));
    }

    /// Pushes onto the stack the value t[`i`] where t is the value at the given `index`
    /// Returns the type of the pushed value
    pub fn getI(lua: *Lua, index: i32, i: Integer) LuaType {
        return @intToEnum(LuaType, c.lua_geti(lua.state, index, i));
    }

    /// If the value at the given `index` has a metatable, the function pushes that metatable onto the stack and returns true
    /// Otherwise false is returned
    pub fn getMetatable(lua: *Lua, index: i32) bool {
        return c.lua_getmetatable(lua.state, index) != 0;
    }

    /// Pushes onto the stack the value t[k] where t is the value at the given `index` and k is the value on the top of the stack
    /// Returns the type of the pushed value
    pub fn getTable(lua: *Lua, index: i32) LuaType {
        return @intToEnum(LuaType, c.lua_gettable(lua.state, index));
    }

    /// Returns the index of the top element in the stack
    /// Because indices start at 1, the result is also equal to the number of elements in the stack
    pub fn getTop(lua: *Lua) i32 {
        return c.lua_gettop(lua.state);
    }

    /// Pushes onto the stack the `n`th user value associated with the full userdata at the given `index`
    /// Returns the type of the pushed value
    pub fn getIUserValue(lua: *Lua, index: i32, n: i32) LuaType {
        return @intToEnum(LuaType, c.lua_getiuservalue(lua.state, index, n));
    }

    /// Moves the top element into the given valid `index` shifting up any elements to make room
    pub fn insert(lua: *Lua, index: i32) void {
        c.lua_insert(lua.state, index);
    }

    /// Returns true if the value at the given `index` is a boolean
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        return c.lua_isboolean(lua.state, index);
    }

    /// Returns true if the value at the given `index` is a CFunction
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        return c.lua_iscfunction(lua.state, index) != 0;
    }

    /// Returns true if the value at the given `index` is a function (C or Lua)
    pub fn isFunction(lua: *Lua, index: i32) bool {
        return c.lua_isfunction(lua.state, index);
    }

    /// Returns true if the value at the given `index` is an integer
    pub fn isInteger(lua: *Lua, index: i32) bool {
        return c.lua_isinteger(lua.state, index) != 0;
    }

    /// Returns true if the value at the given `index` is a light userdata
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        return c.lua_islightuserdata(lua.state, index);
    }

    /// Returns true if the value at the given `index` is nil
    pub fn isNil(lua: *Lua, index: i32) bool {
        return c.lua_isnil(lua.state, index);
    }

    /// Returns true if the given `index` is not valid
    pub fn isNone(lua: *Lua, index: i32) bool {
        return c.lua_isnone(lua.state, index);
    }

    /// Returns true if the given `index` is not valid or if the value at the `index` is nil
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        return c.lua_isnoneornil(lua.state, index);
    }

    /// Returns true if the value at the given `index` is a number
    pub fn isNumber(lua: *Lua, index: i32) bool {
        return c.lua_isnumber(lua.state, index) != 0;
    }

    /// Returns true if the value at the given `index` is a string
    pub fn isString(lua: *Lua, index: i32) bool {
        return c.lua_isstring(lua.state, index) != 0;
    }

    /// Returns true if the value at the given `index` is a table
    pub fn isTable(lua: *Lua, index: i32) bool {
        return c.lua_istable(lua.state, index);
    }

    /// Returns true if the value at the given `index` is a thread
    pub fn isThread(lua: *Lua, index: i32) bool {
        return c.lua_isthread(lua.state, index);
    }

    /// Returns true if the value at the given `index` is a userdata (full or light)
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        return c.lua_isuserdata(lua.state, index) != 0;
    }

    /// Returns true if the given coroutine can yield
    pub fn isYieldable(lua: *Lua) bool {
        return c.lua_isyieldable(lua.state) != 0;
    }

    /// Creates a new independent state and returns its main thread
    pub fn newState(alloc_fn: AllocFunction, data: ?*anyopaque) !Lua {
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
        // lua_pushglobaltable is a macro and c-translate assumes it returns opaque
        // so just reimplement the macro here
        // c.lua_pushglobaltable(lua.state);
        _ = lua.rawGetI(registry_index, ridx_globals);
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
    pub fn pushNumber(lua: *Lua, n: Number) void {
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
        return c.lua_pushthread(lua.state) != 0;
    }

    /// Pushes a copy of the element at the given index onto the stack
    pub fn pushValue(lua: *Lua, index: i32) void {
        c.lua_pushvalue(lua.state, index);
    }

    /// Pushes onto the stack the value t[n], where `t` is the table at the given `index`
    /// Returns the `LuaType` of the pushed value
    pub fn rawGetI(lua: *Lua, index: i32, n: Integer) LuaType {
        return @intToEnum(LuaType, c.lua_rawgeti(lua.state, index, n));
    }

    // TODO: pub fn pushVFString is that even worth?

    /// Sets the top of the stack to `index`
    /// If the new top is greater than the old, new elements are filled with nil
    /// If `index` is 0 all stack elements are removed
    pub fn setTop(lua: *Lua, index: i32) void {
        c.lua_settop(lua.state, index);
    }

    /// Converts the Lua value at the given `index` into a boolean
    /// The Lua value at the index will be considered true unless it is false or nil
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        return c.lua_toboolean(lua.state, index) != 0;
    }

    /// Converts a value at the given `index` into a CFunction
    /// Returns null if the value is not a CFunction
    pub fn toCFunction(lua: *Lua, index: i32) ?CFunction {
        return c.lua_tocfunction(lua.state, index);
    }

    /// Marks the given index in the stack as a to-be-closed slot
    pub fn toClose(lua: *Lua, index: i32) void {
        c.lua_toclose(lua.state, index);
    }

    /// Equivalent to toIntegerX with is_num set to null
    pub fn toInteger(lua: *Lua, index: i32) Integer {
        return lua.toIntegerX(index, null);
    }

    /// Converts the Lua value at the given `index` to a signed integer
    /// The Lua value must be an integer, or a number, or a string convertible to an integer otherwise toIntegerX returns 0
    /// If `is_num` is not null, it's referent is assigned a boolean success value
    pub fn toIntegerX(lua: *Lua, index: i32, is_num: ?*bool) Integer {
        if (is_num) |is_num_ptr| {
            var success: c_int = undefined;
            const result = c.lua_tointegerx(lua.state, index, &success);
            is_num_ptr.* = success != 0;
            return result;
        } else return c.lua_tointegerx(lua.state, index, null);
    }

    /// Converts the Lua value at the given `index` to a C string
    pub fn toLString(lua: *Lua, index: i32, len: ?*usize) [*]const u8 {
        c.lua_tolstring(lua.state, index, len);
    }

    /// Equivalent to toNumberX with is_num set to null
    pub fn toNumber(lua: *Lua, index: i32) Number {
        return lua.toNumberX(index, null);
    }

    /// Converts the Lua value at the given `index` to a float
    /// The Lua value must be a number or a string convertible to a number otherwise toNumberX returns 0
    /// If `is_num` is not null, it's referent is assigned a boolean success value
    pub fn toNumberX(lua: *Lua, index: i32, is_num: ?*bool) Number {
        if (is_num) |is_num_ptr| {
            var success: c_int = undefined;
            const result = c.lua_tonumberx(lua.state, index, &success);
            is_num_ptr.* = success != 0;
            return result;
        } else return c.lua_tonumberx(lua.state, index, null);
    }

    /// Converts the value at the given `index` to an opaque pointer
    pub fn toPointer(lua: *Lua, index: i32) ?*anyopaque {
        return c.lua_topointer(lua.state, index);
    }

    /// Equivalent to toLString with len equal to null
    pub fn toString(lua: *Lua, index: i32) [*]const u8 {
        return lua.toLString(lua, index, null);
    }

    /// Converts the value at the given `index` to a Lua thread (wrapped with a `Lua` struct)
    /// The thread does _not_ contain an allocator because it is not the main thread and should therefore not be used with `deinit()`
    pub fn toThread(lua: *Lua, index: i32) ?Lua {
        const thread = c.lua_tothread(lua.state, index);
        if (thread) |thread_ptr| return Lua{ .state = thread_ptr };
        return null;
    }

    /// If the value at the given `index` is a full userdata, returns its memory-block address
    /// If the value is a light userdata, returns its value (a pointer)
    /// Otherwise returns null
    pub fn toUserdata(lua: *Lua, index: i32) ?*anyopaque {
        return c.lua_touserdata(lua.state, index);
    }

    /// Returns the `LuaType` of the value at the given index
    /// Note that this is equivalent to lua_type but because type is a Zig primitive it is renamed to `typeOf`
    pub fn typeOf(lua: *Lua, index: i32) LuaType {
        return @intToEnum(LuaType, c.lua_type(lua.state, index));
    }

    /// Returns the name of the given `LuaType` as a null-terminated slice
    pub fn typeName(lua: *Lua, t: LuaType) [:0]const u8 {
        return std.mem.span(c.lua_typename(lua.state, @enumToInt(t)));
    }

    // Auxiliary library functions
    //
    // Auxiliary library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    // Ideas of what prefix to start with:
    // * aux
    // * a
    // * x
    // * l

    /// Creates a new Lua state with an allocator using the default libc allocator
    pub fn auxNewState() !Lua {
        const state = c.luaL_newstate() orelse return error.OutOfMemory;
        return Lua{ .state = state };
    }

    // Standard library loading functions
    //
    // TODO: opening libs can run arbitrary Lua code and can throw any error

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

    // use the library with a bad AllocFunction
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

test "basic stack usage" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    // test a variety of push*, to*, and is* calls
    lua.pushBoolean(true);

    try testing.expect(lua.isBoolean(1));
}

test "type of" {
    // TODO: add more tests here after figuring out more type stuff
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    var value: i32 = 0;

    lua.pushBoolean(true);
    lua.pushGlobalTable();
    lua.pushInteger(1);
    lua.pushLightUserdata(&value);
    lua.pushNil();
    lua.pushNumber(0.1);
    _ = lua.pushThread();

    const LuaType = Lua.LuaType;
    try expectEqual(LuaType.boolean, lua.typeOf(1));
    try expectEqual(LuaType.table, lua.typeOf(2));
    try expectEqual(LuaType.number, lua.typeOf(3));
    try expectEqual(LuaType.light_userdata, lua.typeOf(4));
    try expectEqual(LuaType.nil, lua.typeOf(5));
    try expectEqual(LuaType.number, lua.typeOf(6));
    try expectEqual(LuaType.thread, lua.typeOf(7));
    try expectEqual(LuaType.none, lua.typeOf(8));
}

test "typenames" {
    var lua = try Lua.init(testing.allocator);
    defer lua.deinit();

    try testing.expectEqualStrings("no value", lua.typeName(.none));
    try testing.expectEqualStrings("nil", lua.typeName(.nil));
    try testing.expectEqualStrings("boolean", lua.typeName(.boolean));
    try testing.expectEqualStrings("userdata", lua.typeName(.light_userdata));
    try testing.expectEqualStrings("number", lua.typeName(.number));
    try testing.expectEqualStrings("string", lua.typeName(.string));
    try testing.expectEqualStrings("table", lua.typeName(.table));
    try testing.expectEqualStrings("function", lua.typeName(.function));
    try testing.expectEqualStrings("userdata", lua.typeName(.userdata));
    try testing.expectEqualStrings("thread", lua.typeName(.thread));
}
