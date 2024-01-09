//! complete bindings around the Lua C API version 5.3.6
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
/// See https://www.lua.org/manual/5.3/manual.html#lua_Alloc for more details
pub const AllocFn = *const fn (data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque;

/// Operations supported by `Lua.arith()`
pub const ArithOperator = enum(u4) {
    add = c.LUA_OPADD,
    sub = c.LUA_OPSUB,
    mul = c.LUA_OPMUL,
    div = c.LUA_OPDIV,
    int_div = c.LUA_OPIDIV,
    mod = c.LUA_OPMOD,
    pow = c.LUA_OPPOW,
    negate = c.LUA_OPUNM,
    bnot = c.LUA_OPBNOT,
    band = c.LUA_OPBAND,
    bor = c.LUA_OPBOR,
    bxor = c.LUA_OPBXOR,
    shl = c.LUA_OPSHL,
    shr = c.LUA_OPSHR,
};

/// Type for C functions
/// See https://www.lua.org/manual/5.3/manual.html#lua_CFunction for the protocol
pub const CFn = *const fn (state: ?*LuaState) callconv(.C) c_int;

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

    private: *anyopaque = undefined,

    pub const NameType = enum { global, local, method, field, upvalue, other };

    pub const FnType = enum { lua, c, main };

    pub const Options = packed struct {
        @">": bool = false,
        f: bool = false,
        l: bool = false,
        n: bool = false,
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
    /// A memory in a __gc metamethod
    GCMetaMethod,
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
pub const CHookFn = *const fn (state: ?*LuaState, ar: ?*Debug) callconv(.C) void;

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
pub const CContFn = *const fn (state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int;

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
pub const CReaderFn = *const fn (state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8;

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
    pub const err_gcmm = c.LUA_ERRGCMM;
    pub const err_error = c.LUA_ERRERR;
};

// Only used in loadFileX, so no need to group with Status
pub const err_file = c.LUA_ERRFILE;

/// The standard representation for file handles used by the standard IO library
pub const Stream = c.luaL_Stream;

/// The unsigned version of Integer
pub const Unsigned = c.lua_Unsigned;

/// The type of the writer function used by `Lua.dump()`
pub const CWriterFn = *const fn (state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int;

/// A Zig wrapper around the Lua C API
/// Represents a Lua state or thread and contains the entire state of the Lua interpreter
pub const Lua = struct {
    allocator: ?*Allocator = null,
    state: *LuaState,

    const alignment = @alignOf(std.c.max_align_t);

    /// Allows Lua to allocate memory using a Zig allocator passed in via data.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_Alloc for more details
    fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*align(alignment) anyopaque {
        // just like malloc() returns a pointer "which is suitably aligned for any built-in type",
        // the memory allocated by this function should also be aligned for any type that Lua may
        // desire to allocate. use the largest alignment for the target
        const allocator = opaqueCast(Allocator, data.?);

        if (@as(?[*]align(alignment) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
            const prev_slice = prev_ptr[0..osize];

            // when nsize is zero the allocator must behave like free and return null
            if (nsize == 0) {
                allocator.free(prev_slice);
                return null;
            }

            // when nsize is not zero the allocator must behave like realloc
            const new_ptr = allocator.realloc(prev_slice, nsize) catch return null;
            return new_ptr.ptr;
        } else if (nsize == 0) {
            return null;
        } else {
            // ptr is null, allocate a new block of memory
            const new_ptr = allocator.alignedAlloc(u8, alignment, nsize) catch return null;
            return new_ptr.ptr;
        }
    }

    /// Initialize a Lua state with the given allocator
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newstate
    pub fn init(allocator: Allocator) !Lua {
        // the userdata passed to alloc needs to be a pointer with a consistent address
        // so we allocate an Allocator struct to hold a copy of the allocator's data
        // TODO: could we just pass a pointer to the init function?
        const allocator_ptr = allocator.create(Allocator) catch return error.Memory;
        allocator_ptr.* = allocator;

        const state = c.lua_newstate(alloc, allocator_ptr) orelse return error.Memory;
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

    /// Returns the acceptable index index converted into an equivalent absolute index
    /// See https://www.lua.org/manual/5.3/manual.html#lua_absindex
    pub fn absIndex(lua: *Lua, index: i32) i32 {
        return c.lua_absindex(lua.state, index);
    }

    /// Performs an arithmetic or bitwise operation over the value(s) at the top of the stack,
    /// with the value at the top being the second operand. Pushes the result of the operation.
    /// This function follows the semantics of the corresponding Lua operator and may call metamethods
    /// See https://www.lua.org/manual/5.3/manual.html#lua_arith
    pub fn arith(lua: *Lua, op: ArithOperator) void {
        c.lua_arith(lua.state, @intFromEnum(op));
    }

    /// Sets a new panic function and returns the old one
    /// See https://www.lua.org/manual/5.3/manual.html#lua_atpanic
    pub fn atPanic(lua: *Lua, panic_fn: CFn) ?CFn {
        return c.lua_atpanic(lua.state, panic_fn);
    }

    /// Calls a function (or any callable value)
    /// First push the function to be called onto the stack. Then push any arguments onto the stack.
    /// Then call this function. All arguments and the function value are popped, and any results
    /// are pushed onto the stack.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_call
    pub fn call(lua: *Lua, num_args: i32, num_results: i32) void {
        lua.callCont(num_args, num_results, 0, null);
    }

    /// Like call, but allows the called function to yield
    /// See https://www.lua.org/manual/5.3/manual.html#lua_callk
    pub fn callCont(lua: *Lua, num_args: i32, num_results: i32, ctx: Context, k: ?CContFn) void {
        c.lua_callk(lua.state, num_args, num_results, ctx, k);
    }

    /// Ensures that the stack has space for at least n extra arguments
    /// Returns an error if more stack space cannot be allocated
    /// Never shrinks the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_checkstack
    pub fn checkStack(lua: *Lua, n: i32) !void {
        if (c.lua_checkstack(lua.state, n) == 0) return error.Fail;
    }

    /// Release all Lua objects in the state and free all dynamic memory
    /// See https://www.lua.org/manual/5.3/manual.html#lua_close
    pub fn close(lua: *Lua) void {
        c.lua_close(lua.state);
    }

    /// Compares two Lua values
    /// Returns true if the value at index1 satisisfies the comparison with the value at index2
    /// Returns false otherwise, or if any index is not valid
    /// See https://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn compare(lua: *Lua, index1: i32, index2: i32, op: CompareOperator) bool {
        return c.lua_compare(lua.state, index1, index2, @intFromEnum(op)) != 0;
    }

    /// Concatenates the n values at the top of the stack, pops them, and leaves the result at the top
    /// If the number of values is 1, the result is a single value on the stack (nothing changes)
    /// If the number of values is 0, the result is the empty string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_concat
    pub fn concat(lua: *Lua, n: i32) void {
        c.lua_concat(lua.state, n);
    }

    /// Copies the element at from_index to the valid index to_index, replacing the value at that position
    /// See https://www.lua.org/manual/5.3/manual.html#lua_copy
    pub fn copy(lua: *Lua, from_index: i32, to_index: i32) void {
        c.lua_copy(lua.state, from_index, to_index);
    }

    /// Creates a new empty table and pushes onto the stack
    /// num_arr is a hint for how many elements the table will have as a sequence
    /// num_rec is a hint for how many other elements the table will have
    /// Lua may preallocate memory for the table based on the hints
    /// See https://www.lua.org/manual/5.3/manual.html#lua_createtable
    pub fn createTable(lua: *Lua, num_arr: i32, num_rec: i32) void {
        c.lua_createtable(lua.state, num_arr, num_rec);
    }

    /// Dumps a function as a binary chunk
    /// Data is a pointer passed to the writer function
    /// Returns an error if writing was unsuccessful
    /// See https://www.lua.org/manual/5.3/manual.html#lua_dump
    pub fn dump(lua: *Lua, writer: CWriterFn, data: *anyopaque, strip: bool) !void {
        if (c.lua_dump(lua.state, writer, data, @intFromBool(strip)) != 0) return error.Fail;
    }

    /// Raises a Lua error using the value at the top of the stack as the error object
    /// Does a longjump and therefore never returns
    /// See https://www.lua.org/manual/5.3/manual.html#lua_error
    pub fn raiseError(lua: *Lua) noreturn {
        _ = c.lua_error(lua.state);
        unreachable;
    }

    /// Perform a full garbage-collection cycle
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcCollect(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCCOLLECT, 0);
    }

    /// Stops the garbage collector
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcStop(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCSTOP, 0);
    }

    /// Restarts the garbage collector
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcRestart(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCRESTART, 0);
    }

    /// Performs an incremental step of garbage collection corresponding to the allocation of step_size Kbytes
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcStep(lua: *Lua) void {
        _ = c.lua_gc(lua.state, c.LUA_GCSTEP, 0);
    }

    /// Returns the current amount of memory (in Kbytes) in use by Lua
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcCount(lua: *Lua) i32 {
        return c.lua_gc(lua.state, c.LUA_GCCOUNT, 0);
    }

    /// Returns the remainder of dividing the current amount of bytes of memory in use by Lua by 1024
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcCountB(lua: *Lua) i32 {
        return c.lua_gc(lua.state, c.LUA_GCCOUNTB, 0);
    }

    /// Returns a boolean that tells whether the garbage collector is running
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcIsRunning(lua: *Lua) bool {
        return c.lua_gc(lua.state, c.LUA_GCISRUNNING, 0) != 0;
    }

    /// Sets `pause` as the new value for the pause of the collector
    /// Returns the previous value of the pause
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcSetPause(lua: *Lua, pause: i32) i32 {
        return c.lua_gc(lua.state, c.LUA_GCSETPAUSE, pause);
    }

    /// Sets `multiplier` as the new value for the step multiplier of the collector
    /// Returns the previous value of the step multiplier
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcSetStepMul(lua: *Lua, multiplier: i32) i32 {
        return c.lua_gc(lua.state, c.LUA_GCSETSTEPMUL, multiplier);
    }

    /// Returns the memory allocation function of a given state
    /// If data is not null, it is set to the opaque pointer given when the allocator function was set
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getallocf
    pub fn getAllocFn(lua: *Lua, data: ?**anyopaque) AllocFn {
        // Assert cannot be null because it is impossible (and not useful) to pass null
        // to the functions that set the allocator (setallocf and newstate)
        return c.lua_getallocf(lua.state, @ptrCast(data)).?;
    }

    /// Returns a slice of a raw memory area associated with the given Lua state
    /// The application may use this area for any purpose; Lua does not use it for anything
    /// This area has a size of a pointer to void
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getextraspace
    pub fn getExtraSpace(lua: *Lua) []u8 {
        return @as([*]u8, @ptrCast(c.lua_getextraspace(lua.state).?))[0..@sizeOf(isize)];
    }

    /// Pushes onto the stack the value t[key] where t is the value at the given index
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getfield
    pub fn getField(lua: *Lua, index: i32, key: [:0]const u8) LuaType {
        return @enumFromInt(c.lua_getfield(lua.state, index, key.ptr));
    }

    /// Pushes onto the stack the value of the global name and returns the type of that value
    /// Returns an error if the global does not exist (is nil)
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getglobal
    pub fn getGlobal(lua: *Lua, name: [:0]const u8) !LuaType {
        const lua_type: LuaType = @enumFromInt(c.lua_getglobal(lua.state, name.ptr));
        if (lua_type == .nil) return error.Fail;
        return lua_type;
    }

    /// Pushes onto the stack the value t[i] where t is the value at the given index
    /// Returns the type of the pushed value
    /// See https://www.lua.org/manual/5.3/manual.html#lua_geti
    pub fn getIndex(lua: *Lua, index: i32, i: Integer) LuaType {
        return @enumFromInt(c.lua_geti(lua.state, index, i));
    }

    /// Pushes onto the stack the Lua value associated with the full userdata at the given index.
    /// Returns the type of the pushed value.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getuservalue
    pub fn getUserValue(lua: *Lua, index: i32) LuaType {
        return @enumFromInt(c.lua_getuservalue(lua.state, index));
    }

    /// If the value at the given index has a metatable, the function pushes that metatable onto the stack
    /// Otherwise an error is returned
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getmetatable
    pub fn getMetatable(lua: *Lua, index: i32) !void {
        if (c.lua_getmetatable(lua.state, index) == 0) return error.Fail;
    }

    /// Pushes onto the stack the value t[k] where t is the value at the given index and k is the value on the top of the stack
    /// Returns the type of the pushed value
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gettable
    pub fn getTable(lua: *Lua, index: i32) LuaType {
        return @enumFromInt(c.lua_gettable(lua.state, index));
    }

    /// Returns the index of the top element in the stack
    /// Because indices start at 1, the result is also equal to the number of elements in the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gettop
    pub fn getTop(lua: *Lua) i32 {
        return c.lua_gettop(lua.state);
    }

    /// Moves the top element into the given valid `index` shifting up any elements to make room
    /// See https://www.lua.org/manual/5.3/manual.html#lua_insert
    pub fn insert(lua: *Lua, index: i32) void {
        // translate-c cannot translate this macro correctly
        // c.lua_insert(lua.state, index);
        lua.rotate(index, 1);
    }

    /// Returns true if the value at the given index is a boolean
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isboolean
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        return c.lua_isboolean(lua.state, index);
    }

    /// Returns true if the value at the given index is a CFn
    /// See https://www.lua.org/manual/5.3/manual.html#lua_iscfunction
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        return c.lua_iscfunction(lua.state, index) != 0;
    }

    /// Returns true if the value at the given index is a function (C or Lua)
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isfunction
    pub fn isFunction(lua: *Lua, index: i32) bool {
        return c.lua_isfunction(lua.state, index);
    }

    /// Returns true if the value at the given index is an integer
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isinteger
    pub fn isInteger(lua: *Lua, index: i32) bool {
        return c.lua_isinteger(lua.state, index) != 0;
    }

    /// Returns true if the value at the given index is a light userdata
    /// See https://www.lua.org/manual/5.3/manual.html#lua_islightuserdata
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        return c.lua_islightuserdata(lua.state, index);
    }

    /// Returns true if the value at the given index is nil
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isnil
    pub fn isNil(lua: *Lua, index: i32) bool {
        return c.lua_isnil(lua.state, index);
    }

    /// Returns true if the given index is not valid
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isnone
    pub fn isNone(lua: *Lua, index: i32) bool {
        return c.lua_isnone(lua.state, index);
    }

    /// Returns true if the given index is not valid or if the value at the index is nil
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isnoneornil
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        return c.lua_isnoneornil(lua.state, index);
    }

    /// Returns true if the value at the given index is a number
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isnumber
    pub fn isNumber(lua: *Lua, index: i32) bool {
        return c.lua_isnumber(lua.state, index) != 0;
    }

    /// Returns true if the value at the given index is a string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isstring
    pub fn isString(lua: *Lua, index: i32) bool {
        return c.lua_isstring(lua.state, index) != 0;
    }

    /// Returns true if the value at the given index is a table
    /// See https://www.lua.org/manual/5.3/manual.html#lua_istable
    pub fn isTable(lua: *Lua, index: i32) bool {
        return c.lua_istable(lua.state, index);
    }

    /// Returns true if the value at the given index is a thread
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isthread
    pub fn isThread(lua: *Lua, index: i32) bool {
        return c.lua_isthread(lua.state, index);
    }

    /// Returns true if the value at the given index is a userdata (full or light)
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isuserdata
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        return c.lua_isuserdata(lua.state, index) != 0;
    }

    /// Returns true if the given coroutine can yield
    /// See https://www.lua.org/manual/5.3/manual.html#lua_isyieldable
    pub fn isYieldable(lua: *Lua) bool {
        return c.lua_isyieldable(lua.state) != 0;
    }

    /// Pushes the length of the value at the given index onto the stack
    /// Equivalent to the # operator in Lua
    /// See https://www.lua.org/manual/5.3/manual.html#lua_len
    pub fn len(lua: *Lua, index: i32) void {
        c.lua_len(lua.state, index);
    }

    /// Loads a Lua chunk without running it
    /// If there are no errors, pushes the compiled chunk on the top of the stack as a function
    /// See https://www.lua.org/manual/5.3/manual.html#lua_load
    pub fn load(lua: *Lua, reader: CReaderFn, data: *anyopaque, chunk_name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        const ret = c.lua_load(lua.state, reader, data, chunk_name.ptr, mode_str.ptr);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.Syntax,
            StatusCode.err_memory => return error.Memory,
            // lua_load runs pcall, so can also return any result of a pcall error
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_error => return error.MsgHandler,
            StatusCode.err_gcmm => return error.GCMetaMethod,
            else => unreachable,
        }
    }

    /// Creates a new independent state and returns its main thread
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newstate
    pub fn newState(alloc_fn: AllocFn, data: ?*anyopaque) !Lua {
        const state = c.lua_newstate(alloc_fn, data) orelse return error.Memory;
        return Lua{ .state = state };
    }

    /// Creates a new empty table and pushes it onto the stack
    /// Equivalent to createTable(0, 0)
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newtable
    pub fn newTable(lua: *Lua) void {
        c.lua_newtable(lua.state);
    }

    /// Creates a new thread, pushes it on the stack, and returns a Lua state that represents the new thread
    /// The new thread shares the global environment but has a separate execution stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newthread
    pub fn newThread(lua: *Lua) Lua {
        const state = c.lua_newthread(lua.state).?;
        return .{ .state = state };
    }

    /// This function allocates a new userdata of the given type.
    /// Returns a pointer to the Lua-owned data
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newuserdata
    pub fn newUserdata(lua: *Lua, comptime T: type) *T {
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdata(lua.state, @sizeOf(T)).?;
        return opaqueCast(T, ptr);
    }

    /// This function creates and pushes a slice of full userdata onto the stack.
    /// Returns a slice to the Lua-owned data.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newuserdata
    pub fn newUserdataSlice(lua: *Lua, comptime T: type, size: usize) []T {
        // safe to .? because this function throws a Lua error on out of memory
        const ptr = c.lua_newuserdata(lua.state, @sizeOf(T) * size).?;
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    /// Pops a key from the stack, and pushes a key-value pair from the table at the given index
    /// See https://www.lua.org/manual/5.3/manual.html#lua_next
    pub fn next(lua: *Lua, index: i32) bool {
        return c.lua_next(lua.state, index) != 0;
    }

    /// Tries to convert a Lua float into a Lua integer
    /// Returns an error if the conversion was unsuccessful
    /// See https://www.lua.org/manual/5.3/manual.html#lua_numbertointeger
    pub fn numberToInteger(n: Number, i: *Integer) !void {
        // translate-c failure
        // return c.lua_numbertointeger(n, i) != 0;
        const min_float: Number = @floatFromInt(min_integer);
        if (n >= min_float and n < -min_float) {
            i.* = @intFromFloat(n);
        } else return error.Fail;
    }

    /// Calls a function (or callable object) in protected mode
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pcall
    pub fn protectedCall(lua: *Lua, num_args: i32, num_results: i32, msg_handler: i32) !void {
        // The translate-c version of lua_pcall does not type-check so we must rewrite it
        // (macros don't always translate well with translate-c)
        const ret = c.lua_pcallk(lua.state, num_args, num_results, msg_handler, 0, null);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_memory => return error.Memory,
            StatusCode.err_error => return error.MsgHandler,
            StatusCode.err_gcmm => return error.GCMetaMethod,
            else => unreachable,
        }
    }

    /// Behaves exactly like `Lua.protectedCall()` except that it allows the called function to yield
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pcallk
    pub fn protectedCallCont(lua: *Lua, num_args: i32, num_results: i32, msg_handler: i32, ctx: Context, k: CContFn) !void {
        const ret = c.lua_pcallk(lua.state, num_args, num_results, msg_handler, ctx, k);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_memory => return error.Memory,
            StatusCode.err_error => return error.MsgHandler,
            StatusCode.err_gcmm => return error.GCMetaMethod,
            else => unreachable,
        }
    }

    /// Pops `n` elements from the top of the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pop
    pub fn pop(lua: *Lua, n: i32) void {
        lua.setTop(-n - 1);
    }

    /// Pushes a boolean value with value `b` onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushboolean
    pub fn pushBoolean(lua: *Lua, b: bool) void {
        c.lua_pushboolean(lua.state, @intFromBool(b));
    }

    /// Pushes a new Closure onto the stack
    /// `n` tells how many upvalues this function will have
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushcclosure
    pub fn pushClosure(lua: *Lua, c_fn: CFn, n: i32) void {
        c.lua_pushcclosure(lua.state, c_fn, n);
    }

    /// Pushes a function onto the stack.
    /// Equivalent to pushClosure with no upvalues
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushcfunction
    pub fn pushFunction(lua: *Lua, c_fn: CFn) void {
        lua.pushClosure(c_fn, 0);
    }

    /// Push a formatted string onto the stack and return a pointer to the string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushfstring
    pub fn pushFString(lua: *Lua, fmt: [:0]const u8, args: anytype) [*:0]const u8 {
        return @call(.auto, c.lua_pushfstring, .{ lua.state, fmt.ptr } ++ args);
    }

    /// Pushes the global environment onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushglobaltable
    pub fn pushGlobalTable(lua: *Lua) void {
        // lua_pushglobaltable is a macro and c-translate assumes it returns opaque
        // so just reimplement the macro here
        // c.lua_pushglobaltable(lua.state);
        _ = lua.rawGetIndex(registry_index, ridx_globals);
    }

    /// Pushes an integer with value `n` onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushinteger
    pub fn pushInteger(lua: *Lua, n: Integer) void {
        c.lua_pushinteger(lua.state, n);
    }

    /// Pushes a light userdata onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushlightuserdata
    pub fn pushLightUserdata(lua: *Lua, ptr: *anyopaque) void {
        c.lua_pushlightuserdata(lua.state, ptr);
    }

    /// Pushes the bytes onto the stack. Returns a slice pointing to Lua's internal copy of the string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushlstring
    pub fn pushBytes(lua: *Lua, bytes: []const u8) []const u8 {
        return c.lua_pushlstring(lua.state, bytes.ptr, bytes.len)[0..bytes.len];
    }

    /// Pushes a nil value onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushnil
    pub fn pushNil(lua: *Lua) void {
        c.lua_pushnil(lua.state);
    }

    /// Pushes a float with value `n` onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushnumber
    pub fn pushNumber(lua: *Lua, n: Number) void {
        c.lua_pushnumber(lua.state, n);
    }

    /// Pushes a zero-terminated string onto the stack
    /// Lua makes a copy of the string so `str` may be freed immediately after return
    /// Returns a pointer to the internal Lua string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushstring
    pub fn pushString(lua: *Lua, str: [:0]const u8) [:0]const u8 {
        return c.lua_pushstring(lua.state, str.ptr)[0..str.len :0];
    }

    /// Pushes this thread onto the stack
    /// Returns true if this thread is the main thread of its state
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushthread
    pub fn pushThread(lua: *Lua) bool {
        return c.lua_pushthread(lua.state) != 0;
    }

    /// Pushes a copy of the element at the given index onto the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_pushvalue
    pub fn pushValue(lua: *Lua, index: i32) void {
        c.lua_pushvalue(lua.state, index);
    }

    /// Returns true if the two values in indices `index1` and `index2` are primitively equal
    /// Bypasses __eq metamethods
    /// Returns false if not equal, or if any index is invalid
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawequal
    pub fn rawEqual(lua: *Lua, index1: i32, index2: i32) bool {
        return c.lua_rawequal(lua.state, index1, index2) != 0;
    }

    /// Similar to `Lua.getTable()` but does a raw access (without metamethods)
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawget
    pub fn rawGetTable(lua: *Lua, index: i32) LuaType {
        return @enumFromInt(c.lua_rawget(lua.state, index));
    }

    /// Pushes onto the stack the value t[n], where `t` is the table at the given `index`
    /// Returns the `LuaType` of the pushed value
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawgeti
    pub fn rawGetIndex(lua: *Lua, index: i32, n: Integer) LuaType {
        return @enumFromInt(c.lua_rawgeti(lua.state, index, n));
    }

    /// Pushes onto the stack the value t[k] where t is the table at the given `index` and
    /// k is the pointer `p` represented as a light userdata
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawgetp
    pub fn rawGetPtr(lua: *Lua, index: i32, p: *const anyopaque) LuaType {
        return @enumFromInt(c.lua_rawgetp(lua.state, index, p));
    }

    /// Returns the raw length of the value at the given index
    /// For strings it is the length; for tables it is the result of the `#` operator
    /// For userdata it is the size of the block of memory
    /// For other values the call returns 0
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawlen
    pub fn rawLen(lua: *Lua, index: i32) Unsigned {
        return c.lua_rawlen(lua.state, index);
    }

    /// Similar to `Lua.setTable()` but does a raw assignment (without metamethods)
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawset
    pub fn rawSetTable(lua: *Lua, index: i32) void {
        c.lua_rawset(lua.state, index);
    }

    /// Does the equivalent of t[`i`] = v where t is the table at the given `index`
    /// and v is the value at the top of the stack
    /// Pops the value from the stack. Does not use __newindex metavalue
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawseti
    pub fn rawSetIndex(lua: *Lua, index: i32, i: Integer) void {
        c.lua_rawseti(lua.state, index, i);
    }

    /// Does the equivalent of t[p] = v where t is the table at the given `index`
    /// `p` is encoded as a light user data, and v is the value at the top of the stack
    /// Pops the value from the stack. Does not use __newindex metavalue
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rawsetp
    pub fn rawSetPtr(lua: *Lua, index: i32, p: *const anyopaque) void {
        c.lua_rawsetp(lua.state, index, p);
    }

    /// Sets the C function f as the new value of global name
    /// See https://www.lua.org/manual/5.3/manual.html#lua_register
    pub fn register(lua: *Lua, name: [:0]const u8, c_fn: CFn) void {
        c.lua_register(lua.state, name.ptr, c_fn);
    }

    /// Removes the element at the given valid `index` shifting down elements to fill the gap
    /// See https://www.lua.org/manual/5.3/manual.html#lua_remove
    pub fn remove(lua: *Lua, index: i32) void {
        // translate-c cannot translate this macro correctly
        // c.lua_remove(lua.state, index);
        lua.rotate(index, -1);
        lua.pop(1);
    }

    /// Moves the top element into the given valid `index` without shifting any elements,
    /// then pops the top element
    /// See https://www.lua.org/manual/5.3/manual.html#lua_replace
    pub fn replace(lua: *Lua, index: i32) void {
        // translate-c cannot translate this macro correctly
        // c.lua_replace(lua.state, index);
        lua.copy(-1, index);
        lua.pop(1);
    }

    /// Starts and resumes a coroutine in the given thread
    /// See https://www.lua.org/manual/5.3/manual.html#lua_resume
    pub fn resumeThread(lua: *Lua, from: ?Lua, num_args: i32) !ResumeStatus {
        const from_state = if (from) |from_val| from_val.state else null;
        const thread_status = c.lua_resume(lua.state, from_state, num_args);
        switch (thread_status) {
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_memory => return error.Memory,
            StatusCode.err_error => return error.MsgHandler,
            StatusCode.err_gcmm => return error.GCMetaMethod,
            else => return @enumFromInt(thread_status),
        }
    }

    /// Rotates the stack elements between the valid `index` and the top of the stack
    /// The elements are rotated `n` positions in the direction of the top for positive `n`,
    /// and `n` positions in the direction of the bottom for negative `n`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_rotate
    pub fn rotate(lua: *Lua, index: i32, n: i32) void {
        c.lua_rotate(lua.state, index, n);
    }

    /// Changes the allocator function of a given state to `alloc_fn` with userdata `data`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setallocf
    pub fn setAllocF(lua: *Lua, alloc_fn: AllocFn, data: ?*anyopaque) void {
        c.lua_setallocf(lua.state, alloc_fn, data);
    }

    /// Does the equivalent to t[`k`] = v where t is the value at the given `index`
    /// and v is the value on the top of the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setfield
    pub fn setField(lua: *Lua, index: i32, k: [:0]const u8) void {
        c.lua_setfield(lua.state, index, k.ptr);
    }

    /// Pops a value from the stack and sets it as the new value of global `name`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setglobal
    pub fn setGlobal(lua: *Lua, name: [:0]const u8) void {
        c.lua_setglobal(lua.state, name.ptr);
    }

    /// Does the equivalent to t[`n`] = v where t is the value at the given `index`
    /// and v is the value on the top of the stack. Pops the value from the stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_seti
    pub fn setIndex(lua: *Lua, index: i32, n: Integer) void {
        c.lua_seti(lua.state, index, n);
    }

    /// Pops a value from the stack and sets it as the user value associated to
    /// the full userdata at the given index
    /// Returns an error if the userdata does not have that value
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setuservalue
    pub fn setUserValue(lua: *Lua, index: i32) !void {
        c.lua_setuservalue(lua.state, index);
    }

    /// Pops a table or nil from the stack and sets that value as the new metatable for the
    /// value at the given `index`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setmetatable
    pub fn setMetatable(lua: *Lua, index: i32) void {
        // lua_setmetatable always returns 1 so is safe to ignore
        _ = c.lua_setmetatable(lua.state, index);
    }

    /// Does the equivalent to t[k] = v, where t is the value at the given `index`
    /// v is the value on the top of the stack, and k is the value just below the top
    /// See https://www.lua.org/manual/5.3/manual.html#lua_settable
    pub fn setTable(lua: *Lua, index: i32) void {
        c.lua_settable(lua.state, index);
    }

    /// Sets the top of the stack to `index`
    /// If the new top is greater than the old, new elements are filled with nil
    /// If `index` is 0 all stack elements are removed
    /// See https://www.lua.org/manual/5.3/manual.html#lua_settop
    pub fn setTop(lua: *Lua, index: i32) void {
        c.lua_settop(lua.state, index);
    }

    /// Returns the status of this thread
    /// See https://www.lua.org/manual/5.3/manual.html#lua_status
    pub fn status(lua: *Lua) Status {
        return @enumFromInt(c.lua_status(lua.state));
    }

    /// Converts the zero-terminated string `str` to a number, pushes that number onto the stack,
    /// Returns an error if conversion failed
    /// See https://www.lua.org/manual/5.3/manual.html#lua_stringtonumber
    pub fn stringToNumber(lua: *Lua, str: [:0]const u8) !void {
        const size = c.lua_stringtonumber(lua.state, str.ptr);
        if (size == 0) return error.Fail;
    }

    /// Converts the Lua value at the given `index` into a boolean
    /// The Lua value at the index will be considered true unless it is false or nil
    /// See https://www.lua.org/manual/5.3/manual.html#lua_toboolean
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        return c.lua_toboolean(lua.state, index) != 0;
    }

    /// Converts a value at the given `index` into a CFn
    /// Returns an error if the value is not a CFn
    /// See https://www.lua.org/manual/5.3/manual.html#lua_tocfunction
    pub fn toCFunction(lua: *Lua, index: i32) !CFn {
        return c.lua_tocfunction(lua.state, index) orelse return error.Fail;
    }

    /// Converts the Lua value at the given `index` to a signed integer
    /// The Lua value must be an integer, or a number, or a string convertible to an integer otherwise toIntegerX returns 0
    /// Returns an error if the conversion failed
    /// See https://www.lua.org/manual/5.3/manual.html#lua_tointegerx
    pub fn toInteger(lua: *Lua, index: i32) !Integer {
        var success: c_int = undefined;
        const result = c.lua_tointegerx(lua.state, index, &success);
        if (success == 0) return error.Fail;
        return result;
    }

    /// Returns a slice of bytes at the given index
    /// If the value is not a string or number, returns an error
    /// If the value was a number the actual value in the stack will be changed to a string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_tolstring
    pub fn toBytes(lua: *Lua, index: i32) ![:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(lua.state, index, &length)) |ptr| return ptr[0..length :0];
        return error.Fail;
    }

    /// Converts the Lua value at the given `index` to a float
    /// The Lua value must be a number or a string convertible to a number otherwise toNumberX returns 0
    /// Returns an error if the conversion failed
    /// See https://www.lua.org/manual/5.3/manual.html#lua_tonumberx
    pub fn toNumber(lua: *Lua, index: i32) !Number {
        var success: c_int = undefined;
        const result = c.lua_tonumberx(lua.state, index, &success);
        if (success == 0) return error.Fail;
        return result;
    }

    /// Converts the value at the given `index` to an opaque pointer
    /// See https://www.lua.org/manual/5.3/manual.html#lua_topointer
    pub fn toPointer(lua: *Lua, index: i32) !*const anyopaque {
        if (c.lua_topointer(lua.state, index)) |ptr| return ptr;
        return error.Fail;
    }

    /// Converts the Lua value at the given `index` to a zero-terminated many-itemed-pointer (string)
    /// Returns an error if the conversion failed
    /// If the value was a number the actual value in the stack will be changed to a string
    /// See https://www.lua.org/manual/5.3/manual.html#lua_tostring
    pub fn toString(lua: *Lua, index: i32) ![*:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(lua.state, index, &length)) |str| return str;
        return error.Fail;
    }

    /// Converts the value at the given `index` to a Lua thread (wrapped with a `Lua` struct)
    /// The thread does _not_ contain an allocator because it is not the main thread and should therefore not be used with `deinit()`
    /// Returns an error if the value is not a thread
    /// See https://www.lua.org/manual/5.3/manual.html#lua_tothread
    pub fn toThread(lua: *Lua, index: i32) !Lua {
        const thread = c.lua_tothread(lua.state, index);
        if (thread) |thread_ptr| return Lua{ .state = thread_ptr };
        return error.Fail;
    }

    /// Returns a Lua-owned userdata pointer of the given type at the given index.
    /// Works for both light and full userdata.
    /// Returns an error if the value is not a userdata.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_touserdata
    pub fn toUserdata(lua: *Lua, comptime T: type, index: i32) !*T {
        if (c.lua_touserdata(lua.state, index)) |ptr| return opaqueCast(T, ptr);
        return error.Fail;
    }

    /// Returns a Lua-owned userdata slice of the given type at the given index.
    /// Returns an error if the value is not a userdata.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_touserdata
    pub fn toUserdataSlice(lua: *Lua, comptime T: type, index: i32) ![]T {
        if (c.lua_touserdata(lua.state, index)) |ptr| {
            const size = lua.rawLen(index) / @sizeOf(T);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
        }
        return error.Fail;
    }

    /// Returns the `LuaType` of the value at the given index
    /// Note that this is equivalent to lua_type but because type is a Zig primitive it is renamed to `typeOf`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_typeof
    pub fn typeOf(lua: *Lua, index: i32) LuaType {
        return @enumFromInt(c.lua_type(lua.state, index));
    }

    /// Returns the name of the given `LuaType` as a null-terminated slice
    /// See https://www.lua.org/manual/5.3/manual.html#lua_typename
    pub fn typeName(lua: *Lua, t: LuaType) [:0]const u8 {
        return std.mem.span(c.lua_typename(lua.state, @intFromEnum(t)));
    }

    /// Returns the pseudo-index that represents the `i`th upvalue of the running function
    /// See https://www.lua.org/manual/5.3/manual.html#lua_upvalueindex
    pub fn upvalueIndex(i: i32) i32 {
        return c.lua_upvalueindex(i);
    }

    /// Returns the version number of this core
    /// When `caller_version` is true it returns the address of the version running the call
    /// See https://www.lua.org/manual/5.3/manual.html#lua_version
    pub fn version(lua: *Lua, caller_version: bool) *const Number {
        if (caller_version) return c.lua_version(null);
        return c.lua_version(lua.state);
    }

    /// Pops `num` values from the current stack and pushes onto the stack of `to`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_xmove
    pub fn xMove(lua: *Lua, to: Lua, num: i32) void {
        c.lua_xmove(lua.state, to.state, num);
    }

    /// This function is equivalent to `Lua.yieldCont()` but has no continuation
    /// This function never returns
    /// NOTE: look into the lua_yieldk docs about this and debug hooks and noreturn
    /// See https://www.lua.org/manual/5.3/manual.html#lua_yield
    pub fn yield(lua: *Lua, num_results: i32) noreturn {
        // translate-c failed to pass NULL correctly
        _ = c.lua_yieldk(lua.state, num_results, 0, null);
        unreachable;
    }

    /// Yields this coroutine (thread)
    /// This function never returns
    /// See https://www.lua.org/manual/5.3/manual.html#lua_yieldk
    pub fn yieldCont(lua: *Lua, num_results: i32, ctx: Context, k: CContFn) noreturn {
        _ = c.lua_yieldk(lua.state, num_results, ctx, k);
        unreachable;
    }

    // Debug library functions
    //
    // The debug interface functions are included in alphabetical order
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Returns the current hook function
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gethook
    pub fn getHook(lua: *Lua) ?CHookFn {
        return c.lua_gethook(lua.state);
    }

    /// Returns the current hook count
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gethookcount
    pub fn getHookCount(lua: *Lua) i32 {
        return c.lua_gethookcount(lua.state);
    }

    /// Returns the current hook mask
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gethookmask
    pub fn getHookMask(lua: *Lua) HookMask {
        return HookMask.fromInt(c.lua_gethookmask(lua.state));
    }

    /// Gets information about a specific function or function invocation
    /// Returns an error if an invalid option was given, but the valid options
    /// are still handled
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getinfo
    pub fn getInfo(lua: *Lua, options: DebugInfo.Options, info: *DebugInfo) void {
        const str = options.toString();

        var ar: Debug = undefined;
        ar.i_ci = @ptrCast(info.private);

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
        if (options.S) {
            info.source = std.mem.span(ar.source);
            @memcpy(&info.short_src, &ar.short_src);
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
    /// Returns the name of the local variable
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getlocal
    pub fn getLocal(lua: *Lua, info: *DebugInfo, n: i32) ![:0]const u8 {
        var ar: Debug = undefined;
        ar.i_ci = @ptrCast(info.private);
        if (c.lua_getlocal(lua.state, &ar, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Gets information about the interpreter runtime stack
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getstack
    pub fn getStack(lua: *Lua, level: i32) !DebugInfo {
        var ar: Debug = undefined;
        if (c.lua_getstack(lua.state, level, &ar) == 0) return error.Fail;
        return DebugInfo{ .private = ar.i_ci.? };
    }

    /// Gets information about the `n`th upvalue of the closure at index `func_index`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getupvalue
    pub fn getUpvalue(lua: *Lua, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_getupvalue(lua.state, func_index, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Sets the debugging hook function
    /// See https://www.lua.org/manual/5.3/manual.html#lua_sethook
    pub fn setHook(lua: *Lua, hook_fn: CHookFn, mask: HookMask, count: i32) void {
        const hook_mask = HookMask.toInt(mask);
        c.lua_sethook(lua.state, hook_fn, hook_mask, count);
    }

    /// Sets the value of a local variable
    /// Returns an error when the index is greater than the number of active locals
    /// Returns the name of the local variable
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setlocal
    pub fn setLocal(lua: *Lua, info: *DebugInfo, n: i32) ![:0]const u8 {
        var ar: Debug = undefined;
        ar.i_ci = @ptrCast(info.private);
        if (c.lua_setlocal(lua.state, &ar, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Sets the value of a closure's upvalue
    /// Returns the name of the upvalue or an error if the upvalue does not exist
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setupvalue
    pub fn setUpvalue(lua: *Lua, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_setupvalue(lua.state, func_index, n)) |name| {
            return std.mem.span(name);
        }
        return error.Fail;
    }

    /// Returns a unique identifier for the upvalue numbered `n` from the closure index `func_index`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_upvalueid
    pub fn upvalueId(lua: *Lua, func_index: i32, n: i32) !*anyopaque {
        if (c.lua_upvalueid(lua.state, func_index, n)) |ptr| return ptr;
        return error.Fail;
    }

    /// Make the `n1`th upvalue of the Lua closure at index `func_index1` refer to the `n2`th upvalue
    /// of the Lua closure at index `func_index2`
    /// See https://www.lua.org/manual/5.3/manual.html#lua_upvaluejoin
    pub fn upvalueJoin(lua: *Lua, func_index1: i32, n1: i32, func_index2: i32, n2: i32) void {
        c.lua_upvaluejoin(lua.state, func_index1, n1, func_index2, n2);
    }

    // Auxiliary library functions
    //
    // Auxiliary library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Checks whether `cond` is true. Raises an error using `Lua.argError()` if not
    /// Possibly never returns
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_argcheck
    pub fn argCheck(lua: *Lua, cond: bool, arg: i32, extra_msg: [:0]const u8) void {
        // translate-c failed
        if (!cond) lua.argError(arg, extra_msg);
    }

    /// Raises an error reporting a problem with argument `arg` of the C function that called it
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_argerror
    pub fn argError(lua: *Lua, arg: i32, extra_msg: [*:0]const u8) noreturn {
        _ = c.luaL_argerror(lua.state, arg, extra_msg);
        unreachable;
    }

    /// Calls a metamethod
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_callmeta
    pub fn callMeta(lua: *Lua, obj: i32, field: [:0]const u8) !void {
        if (c.luaL_callmeta(lua.state, obj, field.ptr) == 0) return error.Fail;
    }

    /// Checks whether the function has an argument of any type at position `arg`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkany
    pub fn checkAny(lua: *Lua, arg: i32) void {
        c.luaL_checkany(lua.state, arg);
    }

    /// Checks whether the function argument `arg` is an integer (or can be converted to an integer) and returns the integer
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkinteger
    pub fn checkInteger(lua: *Lua, arg: i32) Integer {
        return c.luaL_checkinteger(lua.state, arg);
    }

    /// Checks whether the function argument `arg` is a slice of bytes and returns the slice
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checklstring
    pub fn checkBytes(lua: *Lua, arg: i32) [:0]const u8 {
        var length: usize = 0;
        const str = c.luaL_checklstring(lua.state, arg, &length);
        // luaL_checklstring never returns null (throws lua error)
        return str[0..length :0];
    }

    /// Checks whether the function argument `arg` is a number and returns the number
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checknumber
    pub fn checkNumber(lua: *Lua, arg: i32) Number {
        return c.luaL_checknumber(lua.state, arg);
    }

    /// Checks whether the function argument `arg` is a string and searches for the enum value with the same name in `T`.
    /// `default` is used as a default value when not null
    /// Returns the enum value found
    /// Useful for mapping Lua strings to Zig enums
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkoption
    pub fn checkOption(lua: *Lua, comptime T: type, arg: i32, default: ?T) T {
        const name = blk: {
            if (default) |defaultName| {
                break :blk lua.optBytes(arg, @tagName(defaultName));
            } else {
                break :blk lua.checkBytes(arg);
            }
        };

        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return @enumFromInt(field.value);
            }
        }

        return lua.argError(arg, lua.pushFString("invalid option '%s'", .{name.ptr}));
    }

    /// Grows the stack size to top + `size` elements, raising an error if the stack cannot grow to that size
    /// `msg` is an additional text to go into the error message
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkstack
    pub fn checkStackErr(lua: *Lua, size: i32, msg: ?[*:0]const u8) void {
        c.luaL_checkstack(lua.state, size, msg);
    }

    /// Checks whether the function argument `arg` is a string and returns the string
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkstring
    pub fn checkString(lua: *Lua, arg: i32) [*:0]const u8 {
        return c.luaL_checklstring(lua.state, arg, null);
    }

    /// Checks whether the function argument `arg` has type `t`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checktype
    pub fn checkType(lua: *Lua, arg: i32, t: LuaType) void {
        c.luaL_checktype(lua.state, arg, @intFromEnum(t));
    }

    /// Checks whether the function argument `arg` is a userdata of the type `name`
    /// Returns a pointer to the userdata
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkudata
    pub fn checkUserdata(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) *T {
        // the returned pointer will not be null
        return opaqueCast(T, c.luaL_checkudata(lua.state, arg, name.ptr).?);
    }

    /// Checks whether the function argument `arg` is a userdata of the type `name`
    /// Returns a Lua-owned userdata slice
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkudata
    pub fn checkUserdataSlice(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) []T {
        // the returned pointer will not be null
        const ptr = c.luaL_checkudata(lua.state, arg, name.ptr).?;
        const size = lua.rawLen(arg) / @sizeOf(T);
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    /// Checks whether the code making the call and the Lua library being called are using
    /// the same version of Lua and the same numeric types.
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkversion
    pub fn checkVersion(lua: *Lua) void {
        return c.luaL_checkversion_(lua.state, c.LUA_VERSION_NUM, c.LUAL_NUMSIZES);
    }

    /// Loads and runs the given file
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_dofile
    pub fn doFile(lua: *Lua, file_name: [:0]const u8) !void {
        // translate-c failure
        try lua.loadFile(file_name, .binary_text);
        try lua.protectedCall(0, mult_return, 0);
    }

    /// Loads and runs the given string
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_dostring
    pub fn doString(lua: *Lua, str: [:0]const u8) !void {
        // trnaslate-c failure
        try lua.loadString(str);
        try lua.protectedCall(0, mult_return, 0);
    }

    /// Raises an error
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_error
    pub fn raiseErrorStr(lua: *Lua, fmt: [:0]const u8, args: anytype) noreturn {
        _ = @call(.auto, c.luaL_error, .{ lua.state, fmt.ptr } ++ args);
        unreachable;
    }

    /// This function produces the return values for process-related functions in the standard library
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_execresult
    pub fn execResult(lua: *Lua, stat: i32) i32 {
        return c.luaL_execresult(lua.state, stat);
    }

    /// This function produces the return values for file-related functions in the standard library
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_fileresult
    pub fn fileResult(lua: *Lua, stat: i32, file_name: [:0]const u8) i32 {
        return c.luaL_fileresult(lua.state, stat, file_name.ptr);
    }

    /// Pushes onto the stack the field `e` from the metatable of the object at index `obj`
    /// and returns the type of the pushed value
    /// TODO: possibly return an error if nil
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_getmetafield
    pub fn getMetaField(lua: *Lua, obj: i32, field: [:0]const u8) !LuaType {
        const val_type: LuaType = @enumFromInt(c.luaL_getmetafield(lua.state, obj, field.ptr));
        if (val_type == .nil) return error.Fail;
        return val_type;
    }

    /// Pushes onto the stack the metatable associated with the name `type_name` in the registry
    /// or nil if there is no metatable associated with that name. Returns the type of the pushed value
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_getmetatable
    pub fn getMetatableRegistry(lua: *Lua, table_name: [:0]const u8) LuaType {
        return @enumFromInt(c.luaL_getmetatable(lua.state, table_name.ptr));
    }

    /// Ensures that the value t[`field`], where t is the value at `index`, is a table, and pushes that table onto the stack.
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_getsubtable
    pub fn getSubtable(lua: *Lua, index: i32, field: [:0]const u8) !void {
        if (c.luaL_getsubtable(lua.state, index, field.ptr) == 0) return error.Fail;
    }

    /// Creates a copy of string `str`, replacing any occurrence of the string `pat` with the string `rep`
    /// Pushes the resulting string on the stack and returns it.
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_gsub
    pub fn globalSub(lua: *Lua, str: [:0]const u8, pat: [:0]const u8, rep: [:0]const u8) [:0]const u8 {
        return std.mem.span(c.luaL_gsub(lua.state, str.ptr, pat.ptr, rep.ptr));
    }

    /// Returns the "length" of the value at the given index as a number
    /// it is equivalent to the '#' operator in Lua
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_len
    pub fn lenRaiseErr(lua: *Lua, index: i32) i64 {
        return c.luaL_len(lua.state, index);
    }

    /// Loads a buffer as a Lua chunk
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_loadbufferx
    pub fn loadBuffer(lua: *Lua, buf: []const u8, name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        switch (c.luaL_loadbufferx(lua.state, buf.ptr, buf.len, name.ptr, mode_str.ptr)) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.Syntax,
            StatusCode.err_memory => return error.Memory,
            else => unreachable,
        }
    }

    /// Loads a file as a Lua chunk
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_loadfilex
    pub fn loadFile(lua: *Lua, file_name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        const ret = c.luaL_loadfilex(lua.state, file_name.ptr, mode_str.ptr);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.Syntax,
            StatusCode.err_memory => return error.Memory,
            err_file => return error.File,
            // NOTE: the docs mention possible other return types, but I couldn't figure them out
            else => unreachable,
        }
    }

    /// Loads a string as a Lua chunk
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_loadstring
    pub fn loadString(lua: *Lua, str: [:0]const u8) !void {
        const ret = c.luaL_loadstring(lua.state, str.ptr);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.Syntax,
            StatusCode.err_memory => return error.Memory,
            // loadstring runs lua_load which runs pcall, so can also return any result of an pcall error
            StatusCode.err_runtime => return error.Runtime,
            StatusCode.err_error => return error.MsgHandler,
            else => unreachable,
        }
    }

    /// Creates a new table and registers there the functions in `list`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_newlib
    pub fn newLib(lua: *Lua, list: []const FnReg) void {
        // translate-c failure
        lua.checkVersion();
        lua.newLibTable(list);
        lua.setFuncs(list, 0);
    }

    /// Creates a new table with a size optimized to store all entries in the array `list`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_newlibtable
    pub fn newLibTable(lua: *Lua, list: []const FnReg) void {
        // translate-c failure
        lua.createTable(0, @intCast(list.len));
    }

    /// If the registry already has the key `key`, returns an error
    /// Otherwise, creates a new table to be used as a metatable for userdata
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_newmetatable
    pub fn newMetatable(lua: *Lua, key: [:0]const u8) !void {
        if (c.luaL_newmetatable(lua.state, key.ptr) == 0) return error.Fail;
    }

    /// Creates a new Lua state with an allocator using the default libc allocator
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_newstate
    pub fn newStateLibc() !Lua {
        const state = c.luaL_newstate() orelse return error.Memory;
        return Lua{ .state = state };
    }

    // luaL_opt (a macro) really isn't that useful, so not going to implement for now

    /// If the function argument `arg` is an integer, returns the integer
    /// If the argument is absent or nil returns `default`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_optinteger
    pub fn optInteger(lua: *Lua, arg: i32, default: Integer) Integer {
        return c.luaL_optinteger(lua.state, arg, default);
    }

    /// If the function argument `arg` is a slice of bytes, returns the slice
    /// If the argument is absent or nil returns `default`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_optlstring
    pub fn optBytes(lua: *Lua, arg: i32, default: [:0]const u8) [:0]const u8 {
        var length: usize = 0;
        // will never return null because default cannot be null
        const ret: [*]const u8 = c.luaL_optlstring(lua.state, arg, default.ptr, &length);
        if (ret == default.ptr) return default;
        return ret[0..length :0];
    }

    /// If the function argument `arg` is a number, returns the number
    /// If the argument is absent or nil returns `default`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_optnumber
    pub fn optNumber(lua: *Lua, arg: i32, default: Number) Number {
        return c.luaL_optnumber(lua.state, arg, default);
    }

    /// If the function argument `arg` is a string, returns the string
    /// If the argment is absent or nil returns `default`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_optstring
    pub fn optString(lua: *Lua, arg: i32, default: [:0]const u8) [*:0]const u8 {
        // translate-c error
        return c.luaL_optlstring(lua.state, arg, default.ptr, null);
    }

    /// Creates and returns a reference in the table at index `index` for the object on the top of the stack
    /// Pops the object
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_ref
    pub fn ref(lua: *Lua, index: i32) !i32 {
        const ret = c.luaL_ref(lua.state, index);
        return if (ret == ref_nil) error.Fail else ret;
    }

    /// If package.loaded[`mod_name`] is not true, calls the function `open_fn` with `mod_name`
    /// as an argument and sets the call result to package.loaded[`mod_name`]
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_requiref
    pub fn requireF(lua: *Lua, mod_name: [:0]const u8, open_fn: CFn, global: bool) void {
        c.luaL_requiref(lua.state, mod_name.ptr, open_fn, @intFromBool(global));
    }

    /// Registers all functions in the array `fns` into the table on the top of the stack
    /// All functions are created with `num_upvalues` upvalues
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_setfuncs
    pub fn setFuncs(lua: *Lua, funcs: []const FnReg, num_upvalues: i32) void {
        lua.checkStackErr(num_upvalues, "too many upvalues");
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
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_setmetatable
    pub fn setMetatableRegistry(lua: *Lua, table_name: [:0]const u8) void {
        c.luaL_setmetatable(lua.state, table_name.ptr);
    }

    /// This function works like `Lua.checkUserdata()` except it returns a Zig error instead of raising a Lua error on fail
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_testudata
    pub fn testUserdata(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) !*T {
        if (c.luaL_testudata(lua.state, arg, name.ptr)) |ptr| {
            return opaqueCast(T, ptr);
        } else return error.Fail;
    }

    /// This function works like `Lua.checkUserdataSlice()` except it returns a Zig error instead of raising a Lua error on fail
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_checkudata
    pub fn testUserdataSlice(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) ![]T {
        if (c.luaL_testudata(lua.state, arg, name.ptr)) |ptr| {
            const size = lua.rawLen(arg) / @sizeOf(T);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
        } else return error.Fail;
    }

    /// Converts any Lua value at the given index into a string in a reasonable format
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_tolstring
    pub fn toBytesFmt(lua: *Lua, index: i32) [:0]const u8 {
        var length: usize = undefined;
        const ptr = c.luaL_tolstring(lua.state, index, &length);
        return ptr[0..length :0];
    }

    /// Creates and pushes a traceback of the stack of `other`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_traceback
    pub fn traceback(lua: *Lua, other: *Lua, msg: [:0]const u8, level: i32) void {
        c.luaL_traceback(lua.state, other.state, msg.ptr, level);
    }

    /// Returns the name of the type of the value at the given `index`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_typename
    pub fn typeNameIndex(lua: *Lua, index: i32) [:0]const u8 {
        return std.mem.span(c.luaL_typename(lua.state, index));
    }

    /// Releases the reference `r` from the table at index `index`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_unref
    pub fn unref(lua: *Lua, index: i32, r: i32) void {
        c.luaL_unref(lua.state, index, r);
    }

    /// Pushes onto the stack a string identifying the current position of the control
    /// at the call stack `level`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_where
    pub fn where(lua: *Lua, level: i32) void {
        c.luaL_where(lua.state, level);
    }

    // Standard library loading functions

    /// Opens the specified standard library functions
    /// Behaves like openLibs, but allows specifying which libraries
    /// to expose to the global table rather than all of them
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_openlibs
    pub fn open(lua: *Lua, libs: Libs) void {
        if (libs.base) lua.requireF("_G", c.luaopen_base, true);
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
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_openlibs
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
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_buffinit
    pub fn init(buf: *Buffer, lua: Lua) void {
        c.luaL_buffinit(lua.state, &buf.b);
    }

    /// Initialize a Lua string buffer with an initial size
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_buffinitsize
    pub fn initSize(buf: *Buffer, lua: Lua, size: usize) []u8 {
        return c.luaL_buffinitsize(lua.state, &buf.b, size)[0..size];
    }

    /// Internal Lua type for a string buffer
    pub const LuaBuffer = c.luaL_Buffer;

    pub const buffer_size = c.LUAL_BUFFERSIZE;

    /// Adds `byte` to the buffer
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_addchar
    pub fn addChar(buf: *Buffer, byte: u8) void {
        // could not be translated by translate-c
        var lua_buf = &buf.b;
        if (lua_buf.n >= lua_buf.size) _ = buf.prepSize(1);
        lua_buf.b[lua_buf.n] = byte;
        lua_buf.n += 1;
    }

    /// Adds the string to the buffer
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_addlstring
    pub fn addBytes(buf: *Buffer, str: []const u8) void {
        c.luaL_addlstring(&buf.b, str.ptr, str.len);
    }

    /// Adds to the buffer a string of `length` previously copied to the buffer area
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_addsize
    pub fn addSize(buf: *Buffer, length: usize) void {
        // another function translate-c couldn't handle
        // c.luaL_addsize(&buf.b, length);
        var lua_buf = &buf.b;
        lua_buf.n += length;
    }

    /// Adds the zero-terminated string pointed to by `str` to the buffer
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_addstring
    pub fn addString(buf: *Buffer, str: [:0]const u8) void {
        c.luaL_addstring(&buf.b, str.ptr);
    }

    /// Adds the value on the top of the stack to the buffer
    /// Pops the value
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_addvalue
    pub fn addValue(buf: *Buffer) void {
        c.luaL_addvalue(&buf.b);
    }

    /// Equivalent to prepSize with a buffer size of Buffer.buffer_size
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_prepbuffer
    pub fn prep(buf: *Buffer) []u8 {
        return buf.prepSize(buffer_size)[0..buffer_size];
    }

    /// Returns an address to a space of `size` where you can copy a string
    /// to be added to the buffer
    /// you must call `Buffer.addSize` to actually add it to the buffer
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_prepbuffsize
    pub fn prepSize(buf: *Buffer, size: usize) []u8 {
        return c.luaL_prepbuffsize(&buf.b, size)[0..size];
    }

    /// Finishes the use of the buffer leaving the final string on the top of the stack
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_pushresult
    pub fn pushResult(buf: *Buffer) void {
        c.luaL_pushresult(&buf.b);
    }

    /// Equivalent to `Buffer.addSize()` followed by `Buffer.pushResult()`
    /// See https://www.lua.org/manual/5.3/manual.html#luaL_pushresultsize
    pub fn pushResultSize(buf: *Buffer, size: usize) void {
        c.luaL_pushresultsize(&buf.b, size);
    }
};

// Helper functions to make the ziglua API easier to use

/// Casts the opaque pointer to a pointer of the given type with the proper alignment
/// Useful for casting pointers from the Lua API like userdata or other data
pub inline fn opaqueCast(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(@alignCast(ptr));
}

pub const ZigFn = fn (lua: *Lua) i32;
pub const ZigHookFn = fn (lua: *Lua, event: Event, info: *DebugInfo) void;
pub const ZigContFn = fn (lua: *Lua, status: Status, ctx: Context) i32;
pub const ZigReaderFn = fn (lua: *Lua, data: *anyopaque) ?[]const u8;
pub const ZigWriterFn = fn (lua: *Lua, buf: []const u8, data: *anyopaque) bool;

fn TypeOfWrap(comptime T: type) type {
    return switch (T) {
        LuaState => Lua,
        ZigFn => CFn,
        ZigHookFn => CHookFn,
        ZigContFn => CContFn,
        ZigReaderFn => CReaderFn,
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
        LuaState => Lua{ .state = value },
        ZigFn => wrapZigFn(value),
        ZigHookFn => wrapZigHookFn(value),
        ZigContFn => wrapZigContFn(value),
        ZigReaderFn => wrapZigReaderFn(value),
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
            return @call(.always_inline, f, .{&lua});
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
                .private = @ptrCast(ar.?.i_ci),
            };
            @call(.always_inline, f, .{ &lua, @as(Event, @enumFromInt(ar.?.event)), &info });
        }
    }.inner;
}

/// Wrap a ZigContFn in a CContFn for passing to the API
fn wrapZigContFn(comptime f: ZigContFn) CContFn {
    return struct {
        fn inner(state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int {
            // this is called by Lua, state should never be null
            var lua: Lua = .{ .state = state.? };
            return @call(.always_inline, f, .{ &lua, @as(Status, @enumFromInt(status)), ctx });
        }
    }.inner;
}

/// Wrap a ZigReaderFn in a CReaderFn for passing to the API
fn wrapZigReaderFn(comptime f: ZigReaderFn) CReaderFn {
    return struct {
        fn inner(state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8 {
            var lua: Lua = .{ .state = state.? };
            if (@call(.always_inline, f, .{ &lua, data.? })) |buffer| {
                size.* = buffer.len;
                return buffer.ptr;
            } else {
                size.* = 0;
                return null;
            }
        }
    }.inner;
}

/// Wrap a ZigWriterFn in a CWriterFn for passing to the API
fn wrapZigWriterFn(comptime f: ZigWriterFn) CWriterFn {
    return struct {
        fn inner(state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int {
            // this is called by Lua, state should never be null
            var lua: Lua = .{ .state = state.? };
            const buffer = @as([*]const u8, @ptrCast(buf))[0..size];
            const result = @call(.always_inline, f, .{ &lua, buffer, data.? });
            // it makes more sense for the inner writer function to return false for failure,
            // so negate the result here
            return @intFromBool(!result);
        }
    }.inner;
}

/// Export a Zig function to be used as a Zig (C) Module
pub fn exportFn(comptime name: []const u8, comptime func: ZigFn) void {
    const declaration = wrap(func);
    @export(declaration, .{ .name = "luaopen_" ++ name, .linkage = .Strong });
}
