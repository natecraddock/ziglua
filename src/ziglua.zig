//! ziglua.zig: complete bindings around the Lua C API version 5.4.4
//! exposes all Lua functionality, with additional Zig helper functions

const std = @import("std");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

const Allocator = std.mem.Allocator;

// Types
//
// Lua constants and types are declared below in alphabetical order
// For constants that have a logical grouping (like Operators), Zig enums are used for type safety

/// The type of function that Lua uses for all internal allocations and frees
/// `data` is an opaque pointer to any data (the allocator), `ptr` is a pointer to the block being alloced/realloced/freed
/// `osize` is the original size or a code, and `nsize` is the new size
///
/// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
pub const AllocFn = fn (data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque;

/// Operations supported by `Lua.arith()`
/// TODO: use longer names
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
pub const CFn = fn (state: ?*LuaState) callconv(.C) c_int;

/// Operations supported by `Lua.compare()`
pub const CompareOperator = enum(u2) {
    eq = c.LUA_OPEQ,
    lt = c.LUA_OPLT,
    le = c.LUA_OPLE,
};

/// The internal Lua debug structure
const Debug = c.lua_Debug;

/// The Lua debug interface structure
pub const DebugInfo = struct {
    source: [:0]const u8 = undefined,
    src_len: usize = 0,
    short_src: [c.LUA_IDSIZE:0]u8 = undefined,

    name: ?[:0]const u8 = undefined,
    name_what: NameType = undefined,
    what: FnType = undefined,

    current_line: ?i32 = null,
    first_line_defined: ?i32 = null,
    last_line_defined: ?i32 = null,

    num_upvalues: u8 = 0,
    num_params: u8 = 0,

    is_vararg: bool = false,
    is_tail_call: bool = false,

    first_transfer: u16 = 0,
    num_transfer: u16 = 0,

    private: *anyopaque = undefined,

    pub const NameType = enum { global, local, method, field, upvalue, other };

    pub const FnType = enum { lua, c, main };

    pub const Options = packed struct {
        @">": bool = false,
        f: bool = false,
        l: bool = false,
        n: bool = false,
        r: bool = false,
        S: bool = false,
        t: bool = false,
        u: bool = false,
        L: bool = false,

        fn toString(options: Options) [10:0]u8 {
            var str = [_:0]u8{0} ** 10;
            var index: u8 = 0;

            inline for (std.meta.fields(Options)) |field| {
                if (@field(options, field.name)) {
                    str[index] = field.name[0];
                    index += 1;
                }
            }
            while (index < str.len) : (index += 1) str[index] = 0;

            return str;
        }
    };
};

/// The superset of all errors returned from ziglua
pub const Error = error{
    /// A generic failure (used when a function can only fail in one way)
    Fail,
    /// A runtime error
    Runtime,
    /// A syntax error during precompilation
    Syntax,
    /// A memory allocation error
    Memory,
    /// An error while running the message handler
    MsgHandler,
    /// A file-releated error
    File,
};

/// The type of event that triggers a hook
pub const Event = enum(u3) {
    call = c.LUA_HOOKCALL,
    ret = c.LUA_HOOKRET,
    line = c.LUA_HOOKLINE,
    count = c.LUA_HOOKCOUNT,
    tail_call = c.LUA_HOOKTAILCALL,
};

/// Type for arrays of functions to be registered
pub const FnReg = struct {
    name: [:0]const u8,
    func: ?CFn,
};

/// Type for debugging hook functions
pub const CHookFn = fn (state: ?*LuaState, ar: ?*Debug) callconv(.C) void;

/// Specifies on which events the hook will be called
pub const HookMask = packed struct {
    call: bool = false,
    ret: bool = false,
    line: bool = false,
    count: bool = false,

    /// Converts a HookMask to an integer bitmask
    pub fn toInt(mask: HookMask) i32 {
        var bitmask: i32 = 0;
        if (mask.call) bitmask |= mask_call;
        if (mask.ret) bitmask |= mask_ret;
        if (mask.line) bitmask |= mask_line;
        if (mask.count) bitmask |= mask_count;
        return bitmask;
    }

    /// Converts an integer bitmask into a HookMask
    pub fn fromInt(mask: i32) HookMask {
        return .{
            .call = (mask & mask_call) != 0,
            .ret = (mask & mask_ret) != 0,
            .line = (mask & mask_line) != 0,
            .count = (mask & mask_count) != 0,
        };
    }
};

/// Hook event codes
pub const hook_call = c.LUA_HOOKCALL;
pub const hook_count = c.LUA_HOOKCOUNT;
pub const hook_line = c.LUA_HOOKLINE;
pub const hook_ret = c.LUA_HOOKRET;
pub const hook_tail_call = c.LUA_HOOKTAILCALL;

/// Type of integers in Lua (typically an i64)
pub const Integer = c.lua_Integer;

/// Type for continuation-function contexts (usually isize)
pub const Context = isize;

/// Type for continuation functions
pub const CContFn = fn (state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int;

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

/// The type of the opaque structure that points to a thread and the state of a Lua interpreter
pub const LuaState = c.lua_State;

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

/// Modes used for `Lua.load()`
pub const Mode = enum(u2) { binary, text, binary_text };

/// Event masks
pub const mask_call = c.LUA_MASKCALL;
pub const mask_count = c.LUA_MASKCOUNT;
pub const mask_line = c.LUA_MASKLINE;
pub const mask_ret = c.LUA_MASKRET;

/// The maximum integer value that `Integer` can store
pub const max_integer = c.LUA_MAXINTEGER;

/// The minimum integer value that `Integer` can store
pub const min_integer = c.LUA_MININTEGER;

/// The minimum Lua stack available to a function
pub const min_stack = c.LUA_MINSTACK;

/// Option for multiple returns in `Lua.protectedCall()` and `Lua.call()`
pub const mult_return = c.LUA_MULTRET;

/// Type of floats in Lua (typically an f64)
pub const Number = c.lua_Number;

/// The type of the reader function used by `Lua.load()`
pub const CReaderFn = fn (state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8;

/// The possible status of a call to `Lua.resumeThread`
pub const ResumeStatus = enum(u1) {
    ok = StatusCode.ok,
    yield = StatusCode.yield,
};

/// Reference constants
pub const ref_nil = c.LUA_REFNIL;
pub const ref_no = c.LUA_NOREF;

/// Index of the regsitry in the stack (pseudo-index)
pub const registry_index = c.LUA_REGISTRYINDEX;

/// Index of globals in the registry
pub const ridx_globals = c.LUA_RIDX_GLOBALS;

/// Index of the main thread in the registry
pub const ridx_mainthread = c.LUA_RIDX_MAINTHREAD;

/// Status that a thread can be in
/// Usually errors are reported by a Zig error rather than a status enum value
pub const Status = enum(u3) {
    ok = StatusCode.ok,
    yield = StatusCode.yield,
    err_runtime = StatusCode.err_runtime,
    err_syntax = StatusCode.err_syntax,
    err_memory = StatusCode.err_memory,
    err_error = StatusCode.err_error,
};

/// Status codes
/// Not public, because typically Status.ok is returned from a function implicitly;
/// Any function that returns an error usually returns a Zig error, and a void return
/// is an implicit Status.ok.
/// In the rare case that the status code is required from a function, an enum is
/// used for that specific function's return type
const StatusCode = struct {
    pub const ok = c.LUA_OK;
    pub const yield = c.LUA_YIELD;
    pub const err_runtime = c.LUA_ERRRUN;
    pub const err_syntax = c.LUA_ERRSYNTAX;
    pub const err_memory = c.LUA_ERRMEM;
    pub const err_error = c.LUA_ERRERR;
};

// Only used in loadFileX, so no need to group with Status
pub const err_file = c.LUA_ERRFILE;

/// The standard representation for file handles used by the standard IO library
pub const Stream = c.luaL_Stream;

/// The unsigned version of Integer
pub const Unsigned = c.lua_Unsigned;

/// The type of warning functions used by Lua to emit warnings
pub const CWarnFn = fn (data: ?*anyopaque, msg: [*c]const u8, to_cont: c_int) callconv(.C) void;

/// The type of the writer function used by `Lua.dump()`
pub const CWriterFn = fn (state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int;

/// A Zig wrapper around the Lua C API
/// Represents a Lua state or thread and contains the entire state of the Lua interpreter
pub const Lua = struct {
    allocator: ?*Allocator = null,
    state: *LuaState,

    /// Allows Lua to allocate memory using a Zig allocator passed in via data.
    /// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
    fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque {
        _ = osize; // unused

        // just like malloc() returns a pointer "which is suitably aligned for any built-in type",
        // the memory allocated by this function should also be aligned for any type that Lua may
        // desire to allocate. use the largest alignment for the target
        const alignment = @alignOf(std.c.max_align_t);

        // the data pointer is an Allocator, so the @alignCast is safe
        const allocator = opaqueCast(Allocator, data.?);

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
        var allocator_ptr = allocator.create(Allocator) catch return Error.Memory;
        allocator_ptr.* = allocator;

        const state = c.lua_newstate(alloc, allocator_ptr) orelse return Error.Memory;
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
    pub fn atPanic(lua: *Lua, panic_fn: CFn) ?CFn {
        return c.lua_atpanic(lua.state, panic_fn);
    }

    /// Calls a function (or any callable value)
    pub fn call(lua: *Lua, num_args: i32, num_results: i32) void {
        lua.callCont(num_args, num_results, 0, null);
    }

    /// Like `call`, but allows the called function to yield
    pub fn callCont(lua: *Lua, num_args: i32, num_results: i32, ctx: Context, k: ?CContFn) void {
        c.lua_callk(lua.state, num_args, num_results, ctx, k);
    }

    /// Ensures that the stack has space for at least `n` extra arguments
    /// Returns an error if it cannot fulfil the request
    /// Never shrinks the stack
    pub fn checkStack(lua: *Lua, n: i32) !void {
        if (c.lua_checkstack(lua.state, n) == 0) return Error.Fail;
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
    /// Returns an error if writing was unsuccessful
    pub fn dump(lua: *Lua, writer: CWriterFn, data: *anyopaque, strip: bool) !void {
        if (c.lua_dump(lua.state, writer, data, @boolToInt(strip)) != 0) return Error.Fail;
    }

    /// Raises a Lua error using the value at the top of the stack as the error object
    /// Does a longjump and therefore never returns
    pub fn raiseError(lua: *Lua) noreturn {
        _ = c.lua_error(lua.state);
        unreachable;
    }

    /// Perform a full garbage-collection cycle
    pub fn gcCollect(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCCOLLECT);
    }

    /// Stops the garbage collector
    pub fn gcStop(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCSTOP);
    }

    /// Restarts the garbage collector
    pub fn gcRestart(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCRESTART);
    }

    /// Performs an incremental step of garbage collection corresponding to the allocation of `step_size` Kbytes
    pub fn gcStep(lua: *Lua, step_size: i32) void {
        _ = c.lua_gc(lua.state, c.LUA_GCSTEP, step_size);
    }

    /// Returns the current amount of memory (in Kbytes) in use by Lua
    pub fn gcCount(lua: *Lua) i32 {
        return c.lua_gc(lua.state, c.LUA_GCCOUNT);
    }

    /// Returns the remainder of dividing the current amount of bytes of memory in use by Lua by 1024
    pub fn gcCountB(lua: *Lua) i32 {
        return c.lua_gc(lua.state, c.LUA_GCCOUNTB);
    }

    /// Returns a boolean that tells whether the garbage collector is running
    pub fn gcIsRunning(lua: *Lua) bool {
        return c.lua_gc(lua.state, c.LUA_GCISRUNNING) != 0;
    }

    /// Changes the collector to incremental mode
    /// Returns true if the previous mode was generational
    pub fn gcSetIncremental(lua: *Lua, pause: i32, step_mul: i32, step_size: i32) bool {
        return c.lua_gc(lua.state, c.LUA_GCINC, pause, step_mul, step_size) == c.LUA_GCGEN;
    }

    /// Changes the collector to generational mode
    /// Returns true if the previous mode was incremental
    pub fn gcSetGenerational(lua: *Lua, minor_mul: i32, major_mul: i32) bool {
        return c.lua_gc(lua.state, c.LUA_GCGEN, minor_mul, major_mul) == c.LUA_GCINC;
    }

    /// Returns the memory allocation function of a given state
    /// If `data` is not null, it is set to the opaque pointer given when the allocator function was set
    pub fn getAllocF(lua: *Lua, data: ?**anyopaque) AllocFn {
        // Assert cannot be null because it is impossible (and not useful) to pass null
        // to the functions that set the allocator (setallocf and newstate)
        return c.lua_getallocf(lua.state, @ptrCast([*c]?*anyopaque, data)).?;
    }

    /// Returns a slice of a raw memory area associated with the given Lua state
    /// The application may use this area for any purpose; Lua does not use it for anything
    pub fn getExtraSpace(lua: *Lua) []u8 {
        return @ptrCast([*]u8, c.lua_getextraspace(lua.state).?)[0..@sizeOf(isize)];
    }

    /// Pushes onto the stack the value t[key] where t is the value at the given `index`
    pub fn getField(lua: *Lua, index: i32, key: [:0]const u8) LuaType {
        return @intToEnum(LuaType, c.lua_getfield(lua.state, index, key));
    }

    /// Pushes onto the stack the value of the global `name`
    /// Returns an error if the global does not exist (is nil)
    pub fn getGlobal(lua: *Lua, name: [:0]const u8) !void {
        _ = try lua.getGlobalEx(name);
    }

    /// Pushes onto the stack the value of the global `name`. Returns the type of that value
    /// Returns an error if the global does not exist (is nil)
    pub fn getGlobalEx(lua: *Lua, name: [:0]const u8) !LuaType {
        const lua_type = @intToEnum(LuaType, c.lua_getglobal(lua.state, name));
        if (lua_type == .nil) return Error.Fail;
        return lua_type;
    }

    /// Pushes onto the stack the value t[`i`] where t is the value at the given `index`
    /// Returns the type of the pushed value
    pub fn getIndex(lua: *Lua, index: i32, i: Integer) LuaType {
        return @intToEnum(LuaType, c.lua_geti(lua.state, index, i));
    }

    /// Pushes onto the stack the `n`th user value associated with the full userdata at the given `index`
    /// Returns the type of the pushed value
    /// Returns an error if the userdata does not have that value
    pub fn getIndexUserValue(lua: *Lua, index: i32, n: i32) !LuaType {
        const val_type = @intToEnum(LuaType, c.lua_getiuservalue(lua.state, index, n));
        if (val_type == .none) return Error.Fail;
        return val_type;
    }

    /// If the value at the given `index` has a metatable, the function pushes that metatable onto the stack
    /// Otherwise an error is returned
    pub fn getMetatable(lua: *Lua, index: i32) !void {
        if (c.lua_getmetatable(lua.state, index) == 0) return Error.Fail;
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

    /// Moves the top element into the given valid `index` shifting up any elements to make room
    pub fn insert(lua: *Lua, index: i32) void {
        // translate-c cannot translate this macro correctly
        // c.lua_insert(lua.state, index);
        lua.rotate(index, 1);
    }

    /// Returns true if the value at the given `index` is a boolean
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        return c.lua_isboolean(lua.state, index);
    }

    /// Returns true if the value at the given `index` is a CFn
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

    /// Pushes the length of the value at the given `index` onto the stack
    /// Equivalent to the `#` operator in Lua
    pub fn len(lua: *Lua, index: i32) void {
        c.lua_len(lua.state, index);
    }

    /// Loads a Lua chunk without running it
    pub fn load(lua: *Lua, reader: CReaderFn, data: *anyopaque, chunk_name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        const ret = c.lua_load(lua.state, reader, data, chunk_name, mode_str);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return Error.Syntax,
            StatusCode.err_memory => return Error.Memory,
            // lua_load runs pcall, so can also return any result of an pcall error
            StatusCode.err_runtime => return Error.Runtime,
            StatusCode.err_error => return Error.MsgHandler,
            else => unreachable,
        }
    }

    /// Creates a new independent state and returns its main thread
    pub fn newState(alloc_fn: AllocFn, data: ?*anyopaque) !Lua {
        const state = c.lua_newstate(alloc_fn, data) orelse return Error.Memory;
        return Lua{ .state = state };
    }

    /// Creates a new empty table and pushes it onto the stack
    /// Equivalent to `Lua.createTable(lua, 0, 0)`
    pub fn newTable(lua: *Lua) void {
        c.lua_newtable(lua.state);
    }

    /// Creates a new thread, pushes it on the stack, and returns a `Lua` state that represents the new thread
    /// The new thread shares the global environment but has a separate execution stack
    pub fn newThread(lua: *Lua) Lua {
        const state = c.lua_newthread(lua.state).?;
        return .{ .state = state };
    }

    /// This function creates and pushes a new full userdata onto the stack
    /// with `num_uvalue` associated Lua values, plus an associated block of raw memory with `size` bytes
    /// Returns the address of the block of memory
    pub fn newUserdataUV(lua: *Lua, comptime T: type, new_uvalue: i32) *T {
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdatauv(lua.state, @sizeOf(T), new_uvalue).?;
        return opaqueCast(T, ptr);
    }

    /// Pops a key from the stack, and pushes a key-value pair from the table at the given `index`
    pub fn next(lua: *Lua, index: i32) bool {
        return c.lua_next(lua.state, index) != 0;
    }

    /// Tries to convert a Lua float into a Lua integer
    /// Returns an error if the conversion was unsuccessful
    pub fn numberToInteger(n: Number, i: *Integer) !void {
        // translate-c failure
        // return c.lua_numbertointeger(n, i) != 0;
        if (n >= @intToFloat(Number, min_integer) and n < -@intToFloat(Number, min_integer)) {
            i.* = @floatToInt(Integer, n);
        } else return Error.Fail;
    }

    /// Calls a function (or callable object) in protected mode
    pub fn protectedCall(lua: *Lua, num_args: i32, num_results: i32, msg_handler: i32) !void {
        // The translate-c version of lua_pcall does not type-check so we must rewrite it
        // (macros don't always translate well with translate-c)
        const ret = c.lua_pcallk(lua.state, num_args, num_results, msg_handler, 0, null);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_runtime => return Error.Runtime,
            StatusCode.err_memory => return Error.Memory,
            StatusCode.err_error => return Error.MsgHandler,
            else => unreachable,
        }
    }

    /// Behaves exactly like `Lua.protectedCall()` except that it allows the called function to yield
    pub fn protectedCallCont(lua: *Lua, num_args: i32, num_results: i32, msg_handler: i32, ctx: Context, k: CContFn) !void {
        const ret = c.lua_pcallk(lua.state, num_args, num_results, msg_handler, ctx, k);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_runtime => return Error.Runtime,
            StatusCode.err_memory => return Error.Memory,
            StatusCode.err_error => return Error.MsgHandler,
            else => unreachable,
        }
    }

    /// Pops `n` elements from the top of the stack
    pub fn pop(lua: *Lua, n: i32) void {
        lua.setTop(-n - 1);
    }

    /// Pushes a boolean value with value `b` onto the stack
    pub fn pushBoolean(lua: *Lua, b: bool) void {
        c.lua_pushboolean(lua.state, @boolToInt(b));
    }

    /// Pushes a new Closure onto the stack
    /// `n` tells how many upvalues this function will have
    pub fn pushClosure(lua: *Lua, c_fn: CFn, n: i32) void {
        c.lua_pushcclosure(lua.state, c_fn, n);
    }

    /// Pushes a function onto the stack.
    /// Equivalent to pushClosure with no upvalues
    pub fn pushFunction(lua: *Lua, c_fn: CFn) void {
        lua.pushClosure(c_fn, 0);
    }

    /// Push a formatted string onto the stack
    pub fn pushFString(lua: *Lua, fmt: [:0]const u8, args: anytype) void {
        _ = lua.pushFStringEx(fmt, args);
    }

    /// Push a formatted string onto the stack and return a pointer to the string
    pub fn pushFStringEx(lua: *Lua, fmt: [:0]const u8, args: anytype) [*:0]const u8 {
        const ptr = @call(.{}, c.lua_pushfstring, .{ lua.state, fmt } ++ args);
        return @ptrCast([*:0]const u8, ptr);
    }

    /// Pushes the global environment onto the stack
    pub fn pushGlobalTable(lua: *Lua) void {
        // lua_pushglobaltable is a macro and c-translate assumes it returns opaque
        // so just reimplement the macro here
        // c.lua_pushglobaltable(lua.state);
        _ = lua.rawGetIndex(registry_index, ridx_globals);
    }

    /// Pushes an integer with value `n` onto the stack
    pub fn pushInteger(lua: *Lua, n: Integer) void {
        c.lua_pushinteger(lua.state, n);
    }

    /// Pushes a light userdata onto the stack
    pub fn pushLightUserdata(lua: *Lua, ptr: *anyopaque) void {
        c.lua_pushlightuserdata(lua.state, ptr);
    }

    /// Pushes a slice of bytes onto the stack
    pub fn pushBytes(lua: *Lua, bytes: []const u8) void {
        _ = lua.pushBytesEx(bytes);
    }

    /// Pushes the bytes onto the stack. Returns a slice pointing to Lua's internal copy of the string
    pub fn pushBytesEx(lua: *Lua, bytes: []const u8) []const u8 {
        return c.lua_pushlstring(lua.state, bytes.ptr, bytes.len)[0..bytes.len];
    }

    /// Pushes a nil value onto the stack
    pub fn pushNil(lua: *Lua) void {
        c.lua_pushnil(lua.state);
    }

    /// Pushes a float with value `n` onto the stack
    pub fn pushNumber(lua: *Lua, n: Number) void {
        c.lua_pushnumber(lua.state, n);
    }

    /// Pushes a zero-terminated string on to the stack
    pub fn pushString(lua: *Lua, str: [:0]const u8) void {
        _ = lua.pushStringEx(str);
    }

    /// Pushes a zero-terminated string onto the stack
    /// Lua makes a copy of the string so `str` may be freed immediately after return
    /// Returns a pointer to the internal Lua string
    pub fn pushStringEx(lua: *Lua, str: [:0]const u8) [:0]const u8 {
        return c.lua_pushstring(lua.state, str.ptr).?[0..str.len :0];
    }

    /// Pushes this thread onto the stack
    pub fn pushThread(lua: *Lua) void {
        _ = lua.pushThreadEx();
    }

    /// Pushes this thread onto the stack
    /// Returns true if this thread is the main thread of its state
    pub fn pushThreadEx(lua: *Lua) bool {
        return c.lua_pushthread(lua.state) != 0;
    }

    /// Pushes a copy of the element at the given index onto the stack
    pub fn pushValue(lua: *Lua, index: i32) void {
        c.lua_pushvalue(lua.state, index);
    }

    /// Returns true if the two values in indices `index1` and `index2` are primitively equal
    /// Bypasses __eq metamethods
    /// Returns false if not equal, or if any index is invalid
    pub fn rawEqual(lua: *Lua, index1: i32, index2: i32) bool {
        return c.lua_rawequal(lua.state, index1, index2) != 0;
    }

    /// Similar to `Lua.getTable()` but does a raw access (without metamethods)
    pub fn rawGetTable(lua: *Lua, index: i32) LuaType {
        return @intToEnum(LuaType, c.lua_rawget(lua.state, index));
    }

    /// Pushes onto the stack the value t[n], where `t` is the table at the given `index`
    /// Returns the `LuaType` of the pushed value
    pub fn rawGetIndex(lua: *Lua, index: i32, n: Integer) LuaType {
        return @intToEnum(LuaType, c.lua_rawgeti(lua.state, index, n));
    }

    /// Pushes onto the stack the value t[k] where t is the table at the given `index` and
    /// k is the pointer `p` represented as a light userdata
    pub fn rawGetPtr(lua: *Lua, index: i32, p: *const anyopaque) LuaType {
        return @intToEnum(LuaType, c.lua_rawgetp(lua.state, index, p));
    }

    /// Returns the raw length of the value at the given index
    /// For strings it is the length; for tables it is the result of the `#` operator
    /// For userdata it is the size of the block of memory
    /// For other values the call returns 0
    pub fn rawLen(lua: *Lua, index: i32) Unsigned {
        return c.lua_rawlen(lua.state, index);
    }

    /// Similar to `Lua.setTable()` but does a raw assignment (without metamethods)
    pub fn rawSetTable(lua: *Lua, index: i32) void {
        c.lua_rawset(lua.state, index);
    }

    /// Does the equivalent of t[`i`] = v where t is the table at the given `index`
    /// and v is the value at the top of the stack
    /// Pops the value from the stack. Does not use __newindex metavalue
    pub fn rawSetIndex(lua: *Lua, index: i32, i: Integer) void {
        c.lua_rawseti(lua.state, index, i);
    }

    /// Does the equivalent of t[p] = v where t is the table at the given `index`
    /// `p` is encoded as a light user data, and v is the value at the top of the stack
    /// Pops the value from the stack. Does not use __newindex metavalue
    pub fn rawSetPtr(lua: *Lua, index: i32, p: *const anyopaque) void {
        c.lua_rawsetp(lua.state, index, p);
    }

    /// Sets the C function f as the new value of global name
    pub fn register(lua: *Lua, name: [:0]const u8, c_fn: CFn) void {
        c.lua_register(lua.state, name, c_fn);
    }

    /// Removes the element at the given valid `index` shifting down elements to fill the gap
    pub fn remove(lua: *Lua, index: i32) void {
        // translate-c cannot translate this macro correctly
        // c.lua_remove(lua.state, index);
        lua.rotate(index, -1);
        lua.pop(1);
    }

    /// Moves the top element into the given valid `index` without shifting any elements,
    /// then pops the top element
    pub fn replace(lua: *Lua, index: i32) void {
        // translate-c cannot translate this macro correctly
        // c.lua_replace(lua.state, index);
        lua.copy(-1, index);
        lua.pop(1);
    }

    /// Resets a thread, cleaning its call stack and closing all pending to-be-closed variables
    /// Returns an error if an error occured and leaves an error object on top of the stack
    pub fn resetThread(lua: *Lua) !void {
        if (c.lua_resetthread(lua.state) != StatusCode.ok) return Error.Fail;
    }

    /// Starts and resumes a coroutine in the given thread
    pub fn resumeThread(lua: *Lua, from: ?Lua, num_args: i32, num_results: *i32) !ResumeStatus {
        const from_state = if (from) |from_val| from_val.state else null;
        const thread_status = c.lua_resume(lua.state, from_state, num_args, num_results);
        switch (thread_status) {
            StatusCode.err_runtime => return Error.Runtime,
            StatusCode.err_memory => return Error.Memory,
            StatusCode.err_error => return Error.MsgHandler,
            else => return @intToEnum(ResumeStatus, thread_status),
        }
    }

    /// Rotates the stack elements between the valid `index` and the top of the stack
    /// The elements are rotated `n` positions in the direction of the top for positive `n`,
    /// and `n` positions in the direction of the bottom for negative `n`
    pub fn rotate(lua: *Lua, index: i32, n: i32) void {
        c.lua_rotate(lua.state, index, n);
    }

    /// Changes the allocator function of a given state to `alloc_fn` with userdata `data`
    pub fn setAllocF(lua: *Lua, alloc_fn: AllocFn, data: ?*anyopaque) void {
        c.lua_setallocf(lua.state, alloc_fn, data);
    }

    /// Does the equivalent to t[`k`] = v where t is the value at the given `index`
    /// and v is the value on the top of the stack
    pub fn setField(lua: *Lua, index: i32, k: [:0]const u8) void {
        c.lua_setfield(lua.state, index, k);
    }

    /// Pops a value from the stack and sets it as the new value of global `name`
    pub fn setGlobal(lua: *Lua, name: [:0]const u8) void {
        c.lua_setglobal(lua.state, name);
    }

    /// Does the equivalent to t[`n`] = v where t is the value at the given `index`
    /// and v is the value on the top of the stack. Pops the value from the stack
    pub fn setIndex(lua: *Lua, index: i32, n: Integer) void {
        c.lua_seti(lua.state, index, n);
    }

    /// Pops a value from the stack and sets it as the new `n`th user value associated to
    /// the full userdata at the given index
    /// Returns an error if the userdata does not have that value
    pub fn setIndexUserValue(lua: *Lua, index: i32, n: i32) !void {
        if (c.lua_setiuservalue(lua.state, index, n) == 0) return Error.Fail;
    }

    /// Pops a table or nil from the stack and sets that value as the new metatable for the
    /// value at the given `index`
    pub fn setMetatable(lua: *Lua, index: i32) void {
        // lua_setmetatable always returns 1 so is safe to ignore
        _ = c.lua_setmetatable(lua.state, index);
    }

    /// Does the equivalent to t[k] = v, where t is the value at the given `index`
    /// v is the value on the top of the stack, and k is the value just below the top
    pub fn setTable(lua: *Lua, index: i32) void {
        c.lua_settable(lua.state, index);
    }

    /// Sets the top of the stack to `index`
    /// If the new top is greater than the old, new elements are filled with nil
    /// If `index` is 0 all stack elements are removed
    pub fn setTop(lua: *Lua, index: i32) void {
        c.lua_settop(lua.state, index);
    }

    /// Sets the warning function to be used by Lua to emit warnings
    /// The `data` parameter sets the value `data` passed to the warning function
    pub fn setWarnF(lua: *Lua, warn_fn: CWarnFn, data: ?*anyopaque) void {
        c.lua_setwarnf(lua.state, warn_fn, data);
    }

    /// Returns the status of this thread
    pub fn status(lua: *Lua) Status {
        return @intToEnum(Status, c.lua_status(lua.state));
    }

    /// Converts the zero-terminated string `str` to a number, pushes that number onto the stack,
    /// Returns an error if conversion failed
    pub fn stringToNumber(lua: *Lua, str: [:0]const u8) !void {
        const size = c.lua_stringtonumber(lua.state, str);
        if (size == 0) return Error.Fail;
    }

    /// Converts the Lua value at the given `index` into a boolean
    /// The Lua value at the index will be considered true unless it is false or nil
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        return c.lua_toboolean(lua.state, index) != 0;
    }

    /// Converts a value at the given `index` into a CFn
    /// Returns an error if the value is not a CFn
    pub fn toCFunction(lua: *Lua, index: i32) !CFn {
        return c.lua_tocfunction(lua.state, index) orelse return Error.Fail;
    }

    /// Marks the given index in the stack as a to-be-closed slot
    pub fn toClose(lua: *Lua, index: i32) void {
        c.lua_toclose(lua.state, index);
    }

    /// Converts the Lua value at the given `index` to a signed integer
    /// The Lua value must be an integer, or a number, or a string convertible to an integer otherwise toIntegerX returns 0
    /// Returns an error if the conversion failed
    pub fn toInteger(lua: *Lua, index: i32) !Integer {
        var success: c_int = undefined;
        const result = c.lua_tointegerx(lua.state, index, &success);
        if (success == 0) return Error.Fail;
        return result;
    }

    /// Returns a slice of bytes at the given index
    /// If the value is not a string or number, returns an error
    /// If the value was a number the actual value in the stack will be changed to a string
    pub fn toBytes(lua: *Lua, index: i32) ![:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(lua.state, index, &length)) |ptr| return ptr[0..length :0];
        return Error.Fail;
    }

    /// Converts the Lua value at the given `index` to a float
    /// The Lua value must be a number or a string convertible to a number otherwise toNumberX returns 0
    /// Returns an error if the conversion failed
    pub fn toNumber(lua: *Lua, index: i32) !Number {
        var success: c_int = undefined;
        const result = c.lua_tonumberx(lua.state, index, &success);
        if (success == 0) return Error.Fail;
        return result;
    }

    /// Converts the value at the given `index` to an opaque pointer
    pub fn toPointer(lua: *Lua, index: i32) !*const anyopaque {
        if (c.lua_topointer(lua.state, index)) |ptr| return ptr;
        return Error.Fail;
    }

    /// Converts the Lua value at the given `index` to a zero-terminated many-itemed-pointer (string)
    /// Returns an error if the conversion failed
    /// If the value was a number the actual value in the stack will be changed to a string
    pub fn toString(lua: *Lua, index: i32) ![*:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(lua.state, index, &length)) |str| return str;
        return Error.Fail;
    }

    /// Converts the value at the given `index` to a Lua thread (wrapped with a `Lua` struct)
    /// The thread does _not_ contain an allocator because it is not the main thread and should therefore not be used with `deinit()`
    /// Returns an error if the value is not a thread
    pub fn toThread(lua: *Lua, index: i32) !Lua {
        const thread = c.lua_tothread(lua.state, index);
        if (thread) |thread_ptr| return Lua{ .state = thread_ptr };
        return Error.Fail;
    }

    /// If the value at the given `index` is a full userdata, returns its memory-block address
    /// If the value is a light userdata, returns its value (a pointer)
    /// Otherwise returns an error
    pub fn toUserdata(lua: *Lua, index: i32) !*anyopaque {
        if (c.lua_touserdata(lua.state, index)) |ptr| return ptr;
        return Error.Fail;
    }

    /// Returns the `LuaType` of the value at the given index
    /// Note that this is equivalent to lua_type but because type is a Zig primitive it is renamed to `typeOf`
    pub fn typeOf(lua: *Lua, index: i32) LuaType {
        return @intToEnum(LuaType, c.lua_type(lua.state, index));
    }

    /// Returns the name of the given `LuaType` as a null-terminated slice
    pub fn typeName(lua: *Lua, t: LuaType) [*:0]const u8 {
        return c.lua_typename(lua.state, @enumToInt(t));
    }

    /// Returns the pseudo-index that represents the `i`th upvalue of the running function
    pub fn upvalueIndex(i: i32) i32 {
        return c.lua_upvalueindex(i);
    }

    /// Returns the version number of this core
    pub fn version(lua: *Lua) Number {
        return c.lua_version(lua.state);
    }

    /// Emits a warning with the given `msg`
    /// A message with `to_cont` as true should be continued in a subsequent call to the function
    pub fn warning(lua: *Lua, msg: [:0]const u8, to_cont: bool) void {
        c.lua_warning(lua.state, msg, @boolToInt(to_cont));
    }

    /// Pops `num` values from the current stack and pushes onto the stack of `to`
    pub fn xMove(lua: *Lua, to: Lua, num: i32) void {
        c.lua_xmove(lua.state, to.state, num);
    }

    /// This function is equivalent to `Lua.yieldCont()` but has no continuation
    /// NOTE: look into the lua_yieldk docs about this and debug hooks and noreturn
    pub fn yield(lua: *Lua, num_results: i32) noreturn {
        // translate-c failed to pass NULL correctly
        _ = c.lua_yieldk(lua.state, num_results, 0, null);
        unreachable;
    }

    /// Yields this coroutine (thread)
    pub fn yieldCont(lua: *Lua, num_results: i32, ctx: Context, k: CContFn) noreturn {
        _ = c.lua_yieldk(lua.state, num_results, ctx, k);
        unreachable;
    }

    // Debug library functions
    //
    // The debug interface functions are included in alphabetical order
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Returns the current hook function
    pub fn getHook(lua: *Lua) ?CHookFn {
        return c.lua_gethook(lua.state);
    }

    /// Returns the current hook count
    pub fn getHookCount(lua: *Lua) i32 {
        return c.lua_gethookcount(lua.state);
    }

    /// Returns the current hook mask
    pub fn getHookMask(lua: *Lua) HookMask {
        return HookMask.fromInt(c.lua_gethookmask(lua.state));
    }

    /// Gets information about a specific function or function invocation
    /// Returns an error if an invalid option was given, but the valid options
    /// are still handled
    pub fn getInfo(lua: *Lua, options: DebugInfo.Options, info: *DebugInfo) void {
        const str = options.toString();

        var ar: Debug = undefined;
        ar.i_ci = @ptrCast(*c.struct_CallInfo, info.private);

        // should never fail because we are controlling options with the struct param
        _ = c.lua_getinfo(lua.state, &str, &ar);
        // std.debug.assert( != 0);

        // copy data into a struct
        if (options.l) info.current_line = if (ar.currentline == -1) null else ar.currentline;
        if (options.n) {
            info.name = if (ar.name != null) std.mem.span(ar.name) else null;
            info.name_what = blk: {
                const what = std.mem.span(ar.namewhat);
                if (std.mem.eql(u8, "global", what)) break :blk .global;
                if (std.mem.eql(u8, "local", what)) break :blk .local;
                if (std.mem.eql(u8, "method", what)) break :blk .method;
                if (std.mem.eql(u8, "field", what)) break :blk .field;
                if (std.mem.eql(u8, "upvalue", what)) break :blk .upvalue;
                if (what.len == 0) break :blk .other;
                unreachable;
            };
        }
        if (options.r) {
            info.first_transfer = ar.ftransfer;
            info.num_transfer = ar.ntransfer;
        }
        if (options.S) {
            info.source = std.mem.span(ar.source);
            std.mem.copy(u8, &info.short_src, &ar.short_src);
            info.first_line_defined = ar.linedefined;
            info.last_line_defined = ar.lastlinedefined;
            info.what = blk: {
                const what = std.mem.span(ar.what);
                if (std.mem.eql(u8, "Lua", what)) break :blk .lua;
                if (std.mem.eql(u8, "C", what)) break :blk .c;
                if (std.mem.eql(u8, "main", what)) break :blk .main;
                unreachable;
            };
        }
        if (options.t) info.is_tail_call = ar.istailcall != 0;
        if (options.u) {
            info.num_upvalues = ar.nups;
            info.num_params = ar.nparams;
            info.is_vararg = ar.isvararg != 0;
        }
    }

    /// Gets information about a local variable
    pub fn getLocal(lua: *Lua, info: *DebugInfo, n: i32) !void {
        _ = try lua.getLocalEx(info, n);
    }

    /// Gets information about a local variable
    /// Returns the name of the local variable
    pub fn getLocalEx(lua: *Lua, info: *DebugInfo, n: i32) ![:0]const u8 {
        var ar: Debug = undefined;
        ar.i_ci = @ptrCast(*c.struct_CallInfo, info.private);
        if (c.lua_getlocal(lua.state, &ar, n)) |name| {
            return std.mem.span(name);
        }
        return Error.Fail;
    }

    /// Gets information about the interpreter runtime stack
    pub fn getStack(lua: *Lua, level: i32) !DebugInfo {
        var ar: Debug = undefined;
        if (c.lua_getstack(lua.state, level, &ar) == 0) return Error.Fail;
        return DebugInfo{ .private = ar.i_ci.? };
    }

    /// Gets information about the `n`th upvalue of the closure at index `func_index`
    pub fn getUpvalue(lua: *Lua, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_getupvalue(lua.state, func_index, n)) |name| {
            return std.mem.span(name);
        }
        return Error.Fail;
    }

    /// Sets the debugging hook function
    pub fn setHook(lua: *Lua, hook_fn: CHookFn, mask: HookMask, count: i32) void {
        const hook_mask = HookMask.toInt(mask);
        c.lua_sethook(lua.state, hook_fn, hook_mask, count);
    }

    /// Sets the value of a local variable
    pub fn setLocal(lua: *Lua, info: *DebugInfo, n: i32) !void {
        _ = try lua.setLocalEx(info, n);
    }

    /// Sets the value of a local variable
    /// Returns an error when the index is greater than the number of active locals
    /// Returns the name of the local variable
    pub fn setLocalEx(lua: *Lua, info: *DebugInfo, n: i32) ![:0]const u8 {
        var ar: Debug = undefined;
        ar.i_ci = @ptrCast(*c.struct_CallInfo, info.private);
        if (c.lua_setlocal(lua.state, &ar, n)) |name| {
            return std.mem.span(name);
        }
        return Error.Fail;
    }

    /// Sets the value of a closure's upvalue
    /// Returns an error if the upvalu does not exist
    pub fn setUpvalue(lua: *Lua, func_index: i32, n: i32) !void {
        _ = try lua.setUpvalueEx(func_index, n);
    }

    /// Sets the value of a closure's upvalue
    /// Returns the name of the upvalue or an error if the upvalue does not exist
    pub fn setUpvalueEx(lua: *Lua, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_setupvalue(lua.state, func_index, n)) |name| {
            return std.mem.span(name);
        }
        return Error.Fail;
    }

    /// Returns a unique identifier for the upvalue numbered `n` from the closure index `func_index`
    pub fn upvalueId(lua: *Lua, func_index: i32, n: i32) !*anyopaque {
        if (c.lua_upvalueid(lua.state, func_index, n)) |ptr| return ptr;
        return Error.Fail;
    }

    /// Make the `n1`th upvalue of the Lua closure at index `func_index1` refer to the `n2`th upvalue
    /// of the Lua closure at index `func_index2`
    pub fn upvalueJoin(lua: *Lua, func_index1: i32, n1: i32, func_index2: i32, n2: i32) void {
        c.lua_upvaluejoin(lua.state, func_index1, n1, func_index2, n2);
    }

    // Auxiliary library functions
    //
    // Auxiliary library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Checks whether `cond` is true. Raises an error using `Lua.argError()` if not
    /// Possibly never returns
    pub fn argCheck(lua: *Lua, cond: bool, arg: i32, extra_msg: [:0]const u8) void {
        // translate-c failed
        if (cond) lua.typeError(arg, extra_msg);
    }

    /// Raises an error reporting a problem with argument `arg` of the C function that called it
    pub fn argError(lua: *Lua, arg: i32, extra_msg: [:0]const u8) noreturn {
        _ = c.luaL_argerror(lua.state, arg, extra_msg);
        unreachable;
    }

    /// Checks whether `cond` is true. Raises an error using `Lua.typeError()` if not
    /// Possibly never returns
    pub fn argExpected(lua: *Lua, cond: bool, arg: i32, type_name: [:0]const u8) void {
        // translate-c failed
        if (cond) lua.typeError(arg, type_name);
    }

    /// Calls a metamethod
    pub fn callMeta(lua: *Lua, obj: i32, field: [:0]const u8) !void {
        if (c.luaL_callmeta(lua.state, obj, field) == 0) return Error.Fail;
    }

    /// Checks whether the function has an argument of any type at position `arg`
    pub fn checkAny(lua: *Lua, arg: i32) void {
        c.luaL_checkany(lua.state, arg);
    }

    /// Checks whether the function argument `arg` is an integer (or can be converted to an integer) and returns the integer
    pub fn checkInteger(lua: *Lua, arg: i32) Integer {
        return c.luaL_checkinteger(lua.state, arg);
    }

    /// Checks whether the function argument `arg` is a slice of bytes and returns the slice
    pub fn checkBytes(lua: *Lua, arg: i32) [:0]const u8 {
        var length: usize = 0;
        const str = c.luaL_checklstring(lua.state, arg, @ptrCast([*c]usize, &length));
        // luaL_checklstring never returns null (throws lua error)
        return str.?[0..length :0];
    }

    /// Checks whether the function argument `arg` is a number and returns the number
    pub fn checkNumber(lua: *Lua, arg: i32) Number {
        return c.luaL_checknumber(lua.state, arg);
    }

    /// Checks whether the function argument `arg` is a string and searches for the string in the null-terminated array `list`
    /// `default` is used as a default value when not null
    /// Returns the index in the array where the string was found
    pub fn checkOption(lua: *Lua, arg: i32, default: ?[:0]const u8, list: [:null]?[:0]const u8) i32 {
        return c.luaL_checkoption(
            lua.state,
            arg,
            if (default != null) default.?.ptr else null,
            // TODO: check this cast
            @ptrCast([*c]const [*c]const u8, list.ptr),
        );
    }

    /// Grows the stack size to top + `size` elements, raising an error if the stack cannot grow to that size
    /// `msg` is an additional text to go into the error message
    pub fn checkStackAux(lua: *Lua, size: i32, msg: ?[*:0]const u8) void {
        c.luaL_checkstack(lua.state, size, msg);
    }

    /// Checks whether the function argument `arg` is a string and returns the string
    /// TODO: check about lua_tolstring for returning the size
    pub fn checkString(lua: *Lua, arg: i32) [*:0]const u8 {
        return c.luaL_checklstring(lua.state, arg, null);
    }

    /// Checks whether the function argument `arg` has type `t`
    pub fn checkType(lua: *Lua, arg: i32, t: LuaType) void {
        c.luaL_checktype(lua.state, arg, @enumToInt(t));
    }

    /// Checks whether the function argument `arg` is a userdata of the type `type_name`
    /// Returns the userdata's memory-block address
    pub fn checkUserdata(lua: *Lua, arg: i32, type_name: [:0]const u8) *anyopaque {
        return c.luaL_checkudata(lua.state, arg, type_name).?;
    }

    /// Checks whether the code making the call and the Lua library being called are using
    /// the same version of Lua and the same numeric types.
    pub fn checkVersion(lua: *Lua) void {
        return c.luaL_checkversion(lua.state);
    }

    /// Loads and runs the given file
    pub fn doFile(lua: *Lua, file_name: [:0]const u8) !void {
        // translate-c failure
        try lua.loadFile(file_name);
        try lua.protectedCall(0, mult_return, 0);
    }

    /// Loads and runs the given string
    pub fn doString(lua: *Lua, str: [:0]const u8) !void {
        // trnaslate-c failure
        try lua.loadString(str);
        try lua.protectedCall(0, mult_return, 0);
    }

    /// Raises an error
    pub fn raiseErrorAux(lua: *Lua, fmt: [:0]const u8, args: anytype) noreturn {
        @call(.{}, c.luaL_error, .{ lua.state, fmt } ++ args);
    }

    /// This function produces the return values for process-related functions in the standard library
    pub fn exeResult(lua: *Lua, stat: i32) i32 {
        return c.luaL_execresult(lua.state, stat);
    }

    /// This function produces the return values for file-related functions in the standard library
    pub fn fileResult(lua: *Lua, stat: i32, file_name: [:0]const u8) i32 {
        return c.luaL_fileresult(lua.state, stat, file_name);
    }

    /// Pushes onto the stack the field `e` from the metatable of the object at index `obj`
    /// and returns the type of the pushed value
    /// TODO: possibly return an error if nil
    pub fn getMetaField(lua: *Lua, obj: i32, field: [:0]const u8) !LuaType {
        const val_type = @intToEnum(LuaType, c.luaL_getmetafield(lua.state, obj, field));
        if (val_type == .nil) return Error.Fail;
        return val_type;
    }

    /// Pushes onto the stack the metatable associated with the name `type_name` in the registry
    /// or nil if there is no metatable associated with that name. Returns the type of the pushed value
    /// TODO: return error when type is nil?
    pub fn getMetatableAux(lua: *Lua, type_name: [:0]const u8) LuaType {
        return @intToEnum(LuaType, c.luaL_getmetatable(lua.state, type_name));
    }

    /// Ensures that the value t[`field`], where t is the value at `index`, is a table, and pushes that table onto the stack.
    pub fn getSubtable(lua: *Lua, index: i32, field: [:0]const u8) bool {
        return c.luaL_getsubtable(lua.state, index, field) != 0;
    }

    /// Creates a copy of string `str`, replacing any occurrence of the string `pat` with the string `rep`
    /// Pushes the resulting string on the stack and returns it.
    pub fn gSub(lua: *Lua, str: [:0]const u8, pat: [:0]const u8, rep: [:0]const u8) [:0]const u8 {
        return std.mem.span(c.luaL_gsub(lua.state, str, pat, rep));
    }

    /// Returns the "length" of the value at the given index as a number
    /// it is equivalent to the '#' operator in Lua
    pub fn lenAux(lua: *Lua, index: i32) i64 {
        return c.luaL_len(lua.state, index);
    }

    /// The same as `Lua.loadBufferX` with `mode` set to null
    pub fn loadBuffer(lua: *Lua, buf: [:0]const u8, size: usize, name: [:0]const u8) i32 {
        // translate-c failure
        return c.luaL_loadbufferx(lua.state, buf, size, name, null);
    }

    /// Loads a buffer as a Lua chunk
    /// TODO: There isn't a real reason to allow null mofe with loadBuffer
    pub fn loadBufferX(lua: *Lua, buf: [:0]const u8, size: usize, name: [:0]const u8, mode: ?Mode) i32 {
        const mode_str = blk: {
            if (mode == null) break :blk "bt";

            break :blk switch (mode.?) {
                .binary => "b",
                .text => "t",
                .binary_text => "bt",
            };
        };
        return c.luaL_loadbufferx(lua.state, buf, size, name, mode_str);
    }

    /// Equivalent to `Lua.loadFileX()` with mode equal to null
    pub fn loadFile(lua: *Lua, file_name: [:0]const u8) !void {
        return loadFileX(lua, file_name, null);
    }

    /// Loads a file as a Lua chunk
    pub fn loadFileX(lua: *Lua, file_name: [:0]const u8, mode: ?Mode) !void {
        const mode_str = blk: {
            if (mode == null) break :blk "bt";

            break :blk switch (mode.?) {
                .binary => "b",
                .text => "t",
                .binary_text => "bt",
            };
        };
        const ret = c.luaL_loadfilex(lua.state, file_name, mode_str);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return Error.Syntax,
            StatusCode.err_memory => return Error.Memory,
            err_file => return Error.File,
            // NOTE: the docs mention possible other return types, but I couldn't figure them out
            else => unreachable,
        }
    }

    /// Loads a string as a Lua chunk
    pub fn loadString(lua: *Lua, str: [:0]const u8) !void {
        const ret = c.luaL_loadstring(lua.state, str);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return Error.Syntax,
            StatusCode.err_memory => return Error.Memory,
            // loadstring runs lua_load which runs pcall, so can also return any result of an pcall error
            StatusCode.err_runtime => return Error.Runtime,
            StatusCode.err_error => return Error.MsgHandler,
            else => unreachable,
        }
    }

    /// Creates a new table and registers there the functions in `list`
    pub fn newLib(lua: *Lua, list: []const FnReg) void {
        // translate-c failure
        lua.checkVersion();
        lua.newLibTable(list);
        lua.setFuncs(list, 0);
    }

    /// Creates a new table with a size optimized to store all entries in the array `list`
    pub fn newLibTable(lua: *Lua, list: []const FnReg) void {
        // translate-c failure
        lua.createTable(0, @intCast(i32, list.len));
    }

    /// If the registry already has the key `key`, returns an error
    /// Otherwise, creates a new table to be used as a metatable for userdata
    pub fn newMetatable(lua: *Lua, key: [:0]const u8) !void {
        if (c.luaL_newmetatable(lua.state, key) == 0) return Error.Fail;
    }

    /// Creates a new Lua state with an allocator using the default libc allocator
    pub fn newStateAux() !Lua {
        const state = c.luaL_newstate() orelse return Error.Memory;
        return Lua{ .state = state };
    }

    // luaL_opt (a macro) really isn't that useful, so not going to implement for now

    /// If the function argument `arg` is an integer, returns the integer
    /// If the argument is absent or nil returns `default`
    pub fn optInteger(lua: *Lua, arg: i32, default: Integer) Integer {
        return c.luaL_optinteger(lua.state, arg, default);
    }

    /// If the function argument `arg` is a string, returns the string
    /// If the argument is absent or nil returns `default`
    pub fn optLString(lua: *Lua, arg: i32, default: [:0]const u8) []const u8 {
        var length: usize = 0;
        // will never return null because default cannot be null
        const ret: [*]const u8 = c.luaL_optlstring(lua.state, arg, default, &length);
        if (ret == default.ptr) return default;
        return ret[0..length];
    }

    /// If the function argument `arg` is a number, returns the number
    /// If the argument is absent or nil returns `default`
    pub fn optNumber(lua: *Lua, arg: i32, default: Number) Number {
        return c.luaL_optnumber(lua.state, arg, default);
    }

    /// If the function argument `arg` is a string, returns the string
    /// If the argment is absent or nil returns `default`
    pub fn optString(lua: *Lua, arg: i32, default: [:0]const u8) [*:0]const u8 {
        // translate-c error
        return c.luaL_optlstring(lua.state, arg, default, null);
    }

    /// Pushes the fail value onto the stack
    pub fn pushFail(lua: *Lua) void {
        c.luaL_pushfail(lua.state);
    }

    /// Creates and returns a reference in the table at index `index` for the object on the top of the stack
    /// Pops the object
    pub fn ref(lua: *Lua, index: i32) ?i32 {
        const ret = c.luaL_ref(lua.state, index);
        return if (ret == ref_nil) null else ret;
    }

    /// If package.loaded[`mod_name`] is not true, calls the function `open_fn` with `mod_name`
    /// as an argument and sets the call result to package.loaded[`mod_name`]
    pub fn requireF(lua: *Lua, mod_name: [:0]const u8, open_fn: CFn, global: bool) void {
        c.luaL_requiref(lua.state, mod_name, open_fn, @boolToInt(global));
    }

    /// Registers all functions in the array `fns` into the table on the top of the stack
    /// All functions are created with `num_upvalues` upvalues
    pub fn setFuncs(lua: *Lua, funcs: []const FnReg, num_upvalues: i32) void {
        lua.checkStackAux(num_upvalues, "too many upvalues");
        for (funcs) |f| {
            if (f.func) |func| {
                var i: i32 = 0;
                // copy upvalues to the top
                while (i < num_upvalues) : (i += 1) lua.pushValue(-num_upvalues);
                lua.pushClosure(func, num_upvalues);
            } else lua.pushBoolean(false); // register a placeholder
            lua.setField(-(num_upvalues + 2), f.name);
        }
        lua.pop(num_upvalues);
    }

    /// Sets the metatable of the object on the top of the stack as the metatable associated
    /// with `table_name` in the registry
    pub fn setMetatableAux(lua: *Lua, table_name: [:0]const u8) void {
        c.luaL_setmetatable(lua.state, table_name);
    }

    /// This function works like `Lua.checkUserdata()` except it returns null instead of raising an error on fail
    pub fn testUserdata(lua: *Lua, arg: i32, type_name: [:0]const u8) ?*anyopaque {
        return c.luaL_testudata(lua.state, arg, type_name);
    }

    /// Converts any Lua value at the given index into a string in a reasonable format
    pub fn toLStringAux(lua: *Lua, index: i32) []const u8 {
        var length: usize = undefined;
        const ptr = c.luaL_tolstring(lua.state, index, &length);
        return ptr[0..length];
    }

    /// Creates and pushes a traceback of the stack of `other`
    pub fn traceback(lua: *Lua, other: Lua, msg: [:0]const u8, level: i32) void {
        c.luaL_traceback(lua.state, other.state, msg, level);
    }

    /// Raises a type error for the argument `arg` of the C function that called it
    pub fn typeError(lua: *Lua, arg: i32, type_name: [:0]const u8) noreturn {
        _ = c.luaL_typeerror(lua.state, arg, type_name);
        unreachable;
    }

    /// Returns the name of the type of the value at the given `index`
    /// TODO: maybe typeNameIndex?
    pub fn typeNameAux(lua: *Lua, index: i32) [:0]const u8 {
        return std.mem.span(c.luaL_typename(lua.state, index));
    }

    /// Releases the reference `r` from the table at index `index`
    pub fn unref(lua: *Lua, index: i32, r: i32) void {
        c.luaL_unref(lua.state, index, r);
    }

    /// Pushes onto the stack a string identifying the current position of the control
    /// at the call stack `level`
    pub fn where(lua: *Lua, level: i32) void {
        c.luaL_where(lua.state, level);
    }

    // Standard library loading functions

    /// Opens the specified standard library functions
    /// Behaves like openLibs, but allows specifying which libraries
    /// to expose to the global table rather than all of them
    pub fn open(lua: *Lua, libs: Libs) void {
        if (libs.base) lua.requireF(c.LUA_GNAME, c.luaopen_base, true);
        if (libs.coroutine) lua.requireF(c.LUA_COLIBNAME, c.luaopen_coroutine, true);
        if (libs.package) lua.requireF(c.LUA_LOADLIBNAME, c.luaopen_package, true);
        if (libs.string) lua.requireF(c.LUA_STRLIBNAME, c.luaopen_string, true);
        if (libs.utf8) lua.requireF(c.LUA_UTF8LIBNAME, c.luaopen_utf8, true);
        if (libs.table) lua.requireF(c.LUA_TABLIBNAME, c.luaopen_table, true);
        if (libs.math) lua.requireF(c.LUA_MATHLIBNAME, c.luaopen_math, true);
        if (libs.io) lua.requireF(c.LUA_IOLIBNAME, c.luaopen_io, true);
        if (libs.os) lua.requireF(c.LUA_OSLIBNAME, c.luaopen_os, true);
        if (libs.debug) lua.requireF(c.LUA_DBLIBNAME, c.luaopen_debug, true);
    }

    /// Open all standard libraries
    pub fn openLibs(lua: *Lua) void {
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

/// A string buffer allowing for Zig code to build Lua strings piecemeal
/// All LuaBuffer functions are wrapped in this struct to make the API more convenient to use
pub const Buffer = struct {
    b: LuaBuffer = undefined,

    /// Initialize a Lua string buffer
    pub fn init(buf: *Buffer, lua: Lua) void {
        c.luaL_buffinit(lua.state, &buf.b);
    }

    /// Initialize a Lua string buffer with an initial size
    pub fn initSize(buf: *Buffer, lua: Lua, size: usize) []u8 {
        return c.luaL_buffinitsize(lua.state, &buf.b, size)[0..size];
    }

    /// Internal Lua type for a string buffer
    pub const LuaBuffer = c.luaL_Buffer;

    pub const buffer_size = c.LUAL_BUFFERSIZE;

    /// Adds `byte` to the buffer
    pub fn addChar(buf: *Buffer, byte: u8) void {
        // could not be translated by translate-c
        var lua_buf = &buf.b;
        if (lua_buf.n >= lua_buf.size) _ = buf.prepSize(1);
        lua_buf.b[lua_buf.n] = byte;
        lua_buf.n += 1;
    }

    /// Adds a copy of the string `str` to the buffer
    pub fn addGSub(buf: *Buffer, str: [:0]const u8, pat: [:0]const u8, rep: [:0]const u8) void {
        c.luaL_addgsub(&buf.b, str, pat, rep);
    }

    /// Adds the string to the buffer
    pub fn addLString(buf: *Buffer, str: []const u8) void {
        c.luaL_addlstring(&buf.b, @ptrCast([*c]const u8, str), str.len);
    }

    /// Adds to the buffer a string of `length` previously copied to the buffer area
    pub fn addSize(buf: *Buffer, length: usize) void {
        // another function translate-c couldn't handle
        // c.luaL_addsize(&buf.b, length);
        var lua_buf = &buf.b;
        lua_buf.n += length;
    }

    /// Adds the zero-terminated string pointed to by `str` to the buffer
    pub fn addString(buf: *Buffer, str: [:0]const u8) void {
        c.luaL_addstring(&buf.b, str);
    }

    /// Adds the value on the top of the stack to the buffer
    /// Pops the value
    pub fn addValue(buf: *Buffer) void {
        c.luaL_addvalue(&buf.b);
    }

    /// Returns a slice of the current content of the buffer
    /// Any changes to the buffer may invalidate this slice
    pub fn addr(buf: *Buffer) []u8 {
        const length = buf.b.n;
        return c.luaL_buffaddr(&buf.b)[0..length];
    }

    /// Returns the length of the buffer
    pub fn len(buf: *Buffer) usize {
        return c.luaL_bufflen(&buf.b);
    }

    /// Removes `num` bytes from the buffer
    /// TODO: perhaps error check?
    pub fn sub(buf: *Buffer, num: usize) void {
        // Another bug with translate-c
        // c.luaL_buffsub(&buf.b, num);
        var lua_buf = &buf.b;
        lua_buf.n -= num;
    }

    /// Equivalent to prepSize with a buffer size of Buffer.buffer_size
    pub fn prep(buf: *Buffer) []u8 {
        return buf.prepSize(buffer_size)[0..buffer_size];
    }

    /// Returns an address to a space of `size` where you can copy a string
    /// to be added to the buffer
    /// you must call `Buffer.addSize` to actually add it to the buffer
    pub fn prepSize(buf: *Buffer, size: usize) []u8 {
        return c.luaL_prepbuffsize(&buf.b, size)[0..size];
    }

    /// Finishes the use of the buffer leaving the final string on the top of the stack
    pub fn pushResult(buf: *Buffer) void {
        c.luaL_pushresult(&buf.b);
    }

    /// Equivalent to `Buffer.addSize()` followed by `Buffer.pushResult()`
    pub fn pushResultSize(buf: *Buffer, size: usize) void {
        c.luaL_pushresultsize(&buf.b, size);
    }
};

// Helper functions to make the ziglua API easier to use

/// Casts the opaque pointer to a pointer of the given type with the proper alignment
/// Useful for casting pointers from the Lua API like userdata or other data
pub inline fn opaqueCast(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

pub const ZigFn = fn (lua: *Lua) i32;
pub const ZigHookFn = fn (lua: *Lua, event: Event, info: *DebugInfo) void;
pub const ZigContFn = fn (lua: *Lua, status: Status, ctx: Context) i32;
pub const ZigReaderFn = fn (lua: *Lua, data: *anyopaque) ?[]const u8;
pub const ZigWarnFn = fn (data: ?*anyopaque, msg: []const u8, to_cont: bool) void;
pub const ZigWriterFn = fn (lua: *Lua, buf: []const u8, data: *anyopaque) bool;

fn TypeOfWrap(comptime T: type) type {
    return switch (T) {
        LuaState => Lua,
        ZigFn => CFn,
        ZigHookFn => CHookFn,
        ZigContFn => CContFn,
        ZigReaderFn => CReaderFn,
        ZigWarnFn => CWarnFn,
        ZigWriterFn => CWriterFn,
        else => @compileError("unsupported type given to wrap: '" ++ @typeName(T) ++ "'"),
    };
}

/// Wraps the given value for use in the Lua API
/// Supports the following:
/// * `LuaState` => `Lua`
pub fn wrap(comptime value: anytype) TypeOfWrap(@TypeOf(value)) {
    const T = @TypeOf(value);
    return switch (T) {
        // NOTE: should most likely be ?*LuaState and value.?
        LuaState => Lua{ .state = value },
        ZigFn => wrapZigFn(value),
        ZigHookFn => wrapZigHookFn(value),
        ZigContFn => wrapZigContFn(value),
        ZigReaderFn => wrapZigReaderFn(value),
        ZigWarnFn => wrapZigWarnFn(value),
        ZigWriterFn => wrapZigWriterFn(value),
        else => @compileError("unsupported type given to wrap: '" ++ @typeName(T) ++ "'"),
    };
}

/// Wrap a ZigFn in a CFn for passing to the API
fn wrapZigFn(comptime f: ZigFn) CFn {
    return struct {
        fn inner(state: ?*LuaState) callconv(.C) c_int {
            // this is called by Lua, state should never be null
            var lua: Lua = .{ .state = state.? };
            return @call(.{ .modifier = .always_inline }, f, .{&lua});
        }
    }.inner;
}

/// Wrap a ZigHookFn in a CHookFn for passing to the API
fn wrapZigHookFn(comptime f: ZigHookFn) CHookFn {
    return struct {
        fn inner(state: ?*LuaState, ar: ?*Debug) callconv(.C) void {
            // this is called by Lua, state should never be null
            var lua: Lua = .{ .state = state.? };
            var info: DebugInfo = .{
                .current_line = if (ar.?.currentline == -1) null else ar.?.currentline,
                .private = @ptrCast(*anyopaque, ar.?.i_ci),
            };
            @call(.{ .modifier = .always_inline }, f, .{ &lua, @intToEnum(Event, ar.?.event), &info });
        }
    }.inner;
}

/// Wrap a ZigContFn in a CContFn for passing to the API
fn wrapZigContFn(comptime f: ZigContFn) CContFn {
    return struct {
        fn inner(state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int {
            // this is called by Lua, state should never be null
            var lua: Lua = .{ .state = state.? };
            return @call(.{ .modifier = .always_inline }, f, .{ &lua, @intToEnum(Status, status), ctx });
        }
    }.inner;
}

/// Wrap a ZigReaderFn in a CReaderFn for passing to the API
fn wrapZigReaderFn(comptime f: ZigReaderFn) CReaderFn {
    return struct {
        fn inner(state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8 {
            var lua: Lua = .{ .state = state.? };
            if (@call(.{ .modifier = .always_inline }, f, .{ &lua, data.? })) |buffer| {
                size.* = buffer.len;
                return buffer.ptr;
            } else {
                size.* = 0;
                return null;
            }
        }
    }.inner;
}

/// Wrap a ZigWarnFn in a CWarnFn for passing to the API
fn wrapZigWarnFn(comptime f: ZigWarnFn) CWarnFn {
    return struct {
        fn inner(data: ?*anyopaque, msg: [*c]const u8, to_cont: c_int) callconv(.C) void {
            // warning messages emitted from Lua should be null-terminated for display
            var message = std.mem.span(@ptrCast([*:0]const u8, msg));
            @call(.{ .modifier = .always_inline }, f, .{ data, message, to_cont != 0 });
        }
    }.inner;
}

/// Wrap a ZigWriterFn in a CWriterFn for passing to the API
fn wrapZigWriterFn(comptime f: ZigWriterFn) CWriterFn {
    return struct {
        fn inner(state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int {
            // this is called by Lua, state should never be null
            var lua: Lua = .{ .state = state.? };
            const buffer = @ptrCast([*]const u8, buf)[0..size];
            const result = @call(.{ .modifier = .always_inline }, f, .{ &lua, buffer, data.? });
            // it makes more sense for the inner writer function to return false for failure,
            // so negate the result here
            return @boolToInt(!result);
        }
    }.inner;
}
