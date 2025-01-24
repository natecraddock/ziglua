//! Similar to the Lua C API documentation, each function has an indicator to describe how interacts with the stack and which errors it may return.
//!
//! Instead of using the form `[-o, +p, x]`, Ziglua uses the words **Pops**, **Pushes**, and **Errors** for clarity.
//!
//! * **Pops**: how many elements the function pops from the stack.
//! * **Pushes**: how many elements the function pushes onto the stack.
//!   (Any function always pushes its results after popping its arguments.)
//!   * A field in the form `x|y` means the function can push (or pop) x or y elements, depending on the situation
//!   * an interrogation mark `?` means that we cannot know how many elements the function pops/pushes by looking only at its arguments (For instance, they may depend on what is in the stack.)
//! * **Errors**: tells whether the function may raise errors:
//!   * `-` means the function never raises any error
//!   * `m` means the function may raise only out-of-memory errors
//!   * `v` means the function may raise the errors explained in the text
//!   * `e` means the function can run arbitrary Lua code, either directly or through metamethods, and therefore may raise any errors.

const std = @import("std");

pub const def = @import("define.zig");
pub const define = def.define;

const c = @import("c");

const config = @import("config");

/// Lua language version targeted
pub const lang = config.lang;

/// The length of Luau vector values, either 3 or 4.
pub const luau_vector_size = if (config.luau_use_4_vector) 4 else 3;

/// This function is defined in luau.cpp and must be called to define the assertion printer
extern "c" fn zig_registerAssertionHandler() void;

/// This function is defined in luau.cpp and ensures Zig uses the correct free when compiling luau code
extern "c" fn zig_luau_free(ptr: *anyopaque) void;

const Allocator = std.mem.Allocator;

// Types
//
// Lua constants and types are declared below in alphabetical order
// For constants that have a logical grouping (like Operators), Zig enums are used for type safety

const ArithOperator52 = enum(u4) {
    add = c.LUA_OPADD,
    sub = c.LUA_OPSUB,
    mul = c.LUA_OPMUL,
    div = c.LUA_OPDIV,
    mod = c.LUA_OPMOD,
    pow = c.LUA_OPPOW,
    negate = c.LUA_OPUNM,
};

const ArithOperator53 = enum(u4) {
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

/// Operations supported by `Lua.arith()`
pub const ArithOperator = switch (lang) {
    .lua53, .lua54 => ArithOperator53,
    else => ArithOperator52,
};

/// Type for C functions
/// See https://www.lua.org/manual/5.4/manual.html#lua_CFunction for the protocol
pub const CFn = *const fn (state: ?*LuaState) callconv(.C) c_int;

/// Operations supported by `Lua.compare()`
pub const CompareOperator = enum(u2) {
    eq = c.LUA_OPEQ,
    lt = c.LUA_OPLT,
    le = c.LUA_OPLE,
};

/// Type for C userdata destructors
pub const CUserdataDtorFn = *const fn (userdata: *anyopaque) callconv(.C) void;

/// Type for C interrupt callback
pub const CInterruptCallbackFn = *const fn (state: ?*LuaState, gc: c_int) callconv(.C) void;

/// Type for C useratom callback
pub const CUserAtomCallbackFn = *const fn (str: [*c]const u8, len: usize) callconv(.C) i16;

/// The internal Lua debug structure
const Debug = c.lua_Debug;

pub const DebugInfo51 = struct {
    source: [:0]const u8 = undefined,
    src_len: usize = 0,
    short_src: [c.LUA_IDSIZE:0]u8 = undefined,

    name: ?[:0]const u8 = undefined,
    name_what: NameType = undefined,
    what: FnType = undefined,

    current_line: ?i32 = null,
    first_line_defined: ?i32 = null,
    last_line_defined: ?i32 = null,

    is_vararg: bool = false,

    private: c_int = undefined,

    pub const NameType = enum { global, local, method, field, upvalue, other };

    pub const FnType = enum { lua, c, main };

    pub const Options = packed struct {
        @">": bool = false,
        f: bool = false,
        l: bool = false,
        n: bool = false,
        S: bool = false,
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

const DebugInfo52 = struct {
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

/// The Lua debug interface structure
const DebugInfo54 = struct {
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

pub const DebugInfoLuau = struct {
    source: [:0]const u8 = undefined,
    src_len: usize = 0,
    short_src: [c.LUA_IDSIZE:0]u8 = undefined,

    name: ?[:0]const u8 = undefined,
    what: FnType = undefined,

    current_line: ?i32 = null,
    first_line_defined: ?i32 = null,

    is_vararg: bool = false,

    pub const NameType = enum { global, local, method, field, upvalue, other };

    pub const FnType = enum { lua, c, main, tail };

    pub const Options = packed struct {
        f: bool = false,
        l: bool = false,
        n: bool = false,
        s: bool = false,
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

pub const DebugInfo = switch (lang) {
    .lua51, .luajit => DebugInfo51,
    .lua52, .lua53 => DebugInfo52,
    .lua54 => DebugInfo54,
    .luau => DebugInfoLuau,
};

/// The superset of all errors returned from ziglua
pub const Error = error{
    /// A generic failure (used when a function can only fail in one way)
    LuaError,
    /// A runtime error
    LuaRuntime,
    /// A syntax error during precompilation
    LuaSyntax,
    /// A memory allocation error
    OutOfMemory,
    /// An error while running the message handler
    LuaMsgHandler,
    /// A file-releated error
    LuaFile,
} || switch (lang) {
    .lua52, .lua53 => error{
        /// A memory error in a __gc metamethod
        LuaGCMetaMethod,
    },
    else => error{},
};

const Event51 = enum(u3) {
    call = c.LUA_HOOKCALL,
    ret = c.LUA_HOOKRET,
    line = c.LUA_HOOKLINE,
    count = c.LUA_HOOKCOUNT,
};

/// The type of event that triggers a hook
const Event52 = enum(u3) {
    call = c.LUA_HOOKCALL,
    ret = c.LUA_HOOKRET,
    line = c.LUA_HOOKLINE,
    count = c.LUA_HOOKCOUNT,
    tail_call = c.LUA_HOOKTAILCALL,
};

pub const Event = switch (lang) {
    .lua51, .luajit => Event51,
    .lua52, .lua53, .lua54 => Event52,
    // TODO: probably something better than void here
    .luau => void,
};

/// Type for arrays of functions to be registered
pub const FnReg = struct {
    name: [:0]const u8,
    func: ?CFn,
};

/// The index of the global environment table
pub const globals_index = c.LUA_GLOBALSINDEX;

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

pub const Libs51 = packed struct {
    base: bool = false,
    package: bool = false,
    string: bool = false,
    utf8: bool = false,
    table: bool = false,
    math: bool = false,
    io: bool = false,
    os: bool = false,
    debug: bool = false,
};

pub const Libs52 = packed struct {
    base: bool = false,
    coroutine: bool = false,
    package: bool = false,
    string: bool = false,
    table: bool = false,
    math: bool = false,
    io: bool = false,
    os: bool = false,
    debug: bool = false,
    bit: bool = false,
};

pub const Libs53 = packed struct {
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
pub const LuaType = switch (lang) {
    .luau => enum(i5) {
        none = c.LUA_TNONE,
        nil = c.LUA_TNIL,
        boolean = c.LUA_TBOOLEAN,
        light_userdata = c.LUA_TLIGHTUSERDATA,
        number = c.LUA_TNUMBER,
        vector = c.LUA_TVECTOR,
        string = c.LUA_TSTRING,
        table = c.LUA_TTABLE,
        function = c.LUA_TFUNCTION,
        userdata = c.LUA_TUSERDATA,
        thread = c.LUA_TTHREAD,
    },
    else => enum(i5) {
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
    },
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
/// TODO: see where this is used and check if a null can be used instead
const StatusCode = struct {
    pub const ok = if (@hasDecl(c, "LUA_OK")) c.LUA_OK else 0;
    pub const yield = c.LUA_YIELD;
    pub const err_runtime = c.LUA_ERRRUN;
    pub const err_syntax = c.LUA_ERRSYNTAX;
    pub const err_memory = c.LUA_ERRMEM;
    pub const err_error = c.LUA_ERRERR;

    pub const err_gcmm = switch (lang) {
        .lua52, .lua53 => c.LUA_ERRGCMM,
        else => unreachable,
    };
};

// Only used in loadFileX, so no need to group with Status
pub const err_file = c.LUA_ERRFILE;

/// The standard representation for file handles used by the standard IO library
pub const Stream = c.luaL_Stream;

/// The unsigned version of Integer
pub const Unsigned = c.lua_Unsigned;

/// The type of warning functions used by Lua to emit warnings
pub const CWarnFn = switch (lang) {
    .lua54 => *const fn (data: ?*anyopaque, msg: [*c]const u8, to_cont: c_int) callconv(.C) void,
    else => @compileError("CWarnFn not defined"),
};

/// The type of the writer function used by `Lua.dump()`
pub const CWriterFn = *const fn (state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int;

/// For bundling a parsed value with an arena allocator
/// Copied from std.json.Parsed
pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

/// A Zig wrapper around the Lua C API
/// Represents a Lua state or thread and contains the entire state of the Lua interpreter
pub const Lua = opaque {
    const alignment = @alignOf(std.c.max_align_t);

    /// Allows Lua to allocate memory using a Zig allocator passed in via data.
    /// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
    fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*align(alignment) anyopaque {
        // just like malloc() returns a pointer "which is suitably aligned for any built-in type",
        // the memory allocated by this function should also be aligned for any type that Lua may
        // desire to allocate. use the largest alignment for the target
        const allocator_ptr: *Allocator = @ptrCast(@alignCast(data.?));

        if (@as(?[*]align(alignment) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
            const prev_slice = prev_ptr[0..osize];

            // when nsize is zero the allocator must behave like free and return null
            if (nsize == 0) {
                allocator_ptr.free(prev_slice);
                return null;
            }

            // when nsize is not zero the allocator must behave like realloc
            const new_ptr = allocator_ptr.realloc(prev_slice, nsize) catch return null;
            return new_ptr.ptr;
        } else if (nsize == 0) {
            return null;
        } else {
            // ptr is null, allocate a new block of memory
            const new_ptr = allocator_ptr.alignedAlloc(u8, alignment, nsize) catch return null;
            return new_ptr.ptr;
        }
    }

    /// Initialize a Lua state with the given allocator. Use `Lua.deinit()` to close the state and free memory.
    ///
    /// Creates a new independent state and returns its main thread.
    /// Returns NULL if it cannot create the state (due to lack of memory).
    /// The argument f is the allocator function; Lua will do all memory allocation
    /// for this state through this function (see lua_Alloc). The second argument,
    /// ud, is an opaque pointer that Lua passes to the allocator in every call.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_newstate
    pub fn init(a: Allocator) !*Lua {
        if (lang == .luau) zig_registerAssertionHandler();

        // the userdata passed to alloc needs to be a pointer with a consistent address
        // so we allocate an Allocator struct to hold a copy of the allocator's data
        const allocator_ptr = try a.create(Allocator);
        allocator_ptr.* = a;

        // @constCast() is safe here because Lua does not mutate the pointer internally
        if (c.lua_newstate(alloc, allocator_ptr)) |state| {
            return @ptrCast(state);
        } else return error.OutOfMemory;
    }

    /// Deinitialize a Lua state and free all memory
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_close
    pub fn deinit(lua: *Lua) void {
        // First get a reference to the allocator
        var data: ?*Allocator = undefined;
        _ = c.lua_getallocf(@ptrCast(lua), @ptrCast(&data)).?;

        c.lua_close(@ptrCast(lua));

        if (data) |a| {
            const alloc_ = a;
            alloc_.destroy(a);
        }
    }

    /// Returns the `std.mem.Allocator` used to initialize this Lua state
    pub fn allocator(lua: *Lua) Allocator {
        var data: ?*Allocator = undefined;
        _ = c.lua_getallocf(@ptrCast(lua), @ptrCast(&data)).?;

        // The pointer should never be null because the only way to create a Lua state requires
        // passing a Zig allocator.
        // Although the Allocator is passed to Lua as a pointer, return a copy to make use more convenient.
        return data.?.*;
    }

    // Library functions
    //
    // Library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Converts the acceptable index idx into an equivalent absolute index (that is, one that does not depend on the stack size)
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_absindex
    pub fn absIndex(lua: *Lua, index: i32) i32 {
        switch (lang) {
            .lua51, .luajit => {
                if (index > 0 or index <= registry_index) {
                    return index;
                } else {
                    const result = lua.getTop() + 1 + index;
                    return @intCast(result);
                }
            },
            else => {
                return c.lua_absindex(@ptrCast(lua), index);
            },
        }
    }

    /// Arithmetic functions for values on the stack
    ///
    /// Performs an arithmetic or bitwise operation over the two values (or one, in the
    /// case of negations) at the top of the stack, with the value on the top being the
    /// second operand, pops these values, and pushes the result of the operation. The
    /// function follows the semantics of the corresponding Lua operator (that is, it
    /// may call metamethods).
    ///
    /// Not implemented in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `(2|1)`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_arith
    pub fn arith(lua: *Lua, op: ArithOperator) void {
        c.lua_arith(@ptrCast(lua), @intFromEnum(op));
    }

    /// Sets a new panic function and returns the old one
    ///
    /// Not implemented in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_atpanic
    pub fn atPanic(lua: *Lua, panic_fn: CFn) ?CFn {
        return c.lua_atpanic(@ptrCast(lua), panic_fn);
    }

    pub const CallArgs = struct {
        /// The number of args passed to the function from the stack
        args: i32 = 0,
        /// The number of results the function pushes to the stack upon returning
        results: i32 = 0,
    };

    /// Calls a function
    ///
    /// Like regular Lua calls, `Lua.call()` respects the `__call` metamethod. So, here the word "function" means any callable value.
    ///
    /// To do a call you must use the following protocol:
    /// * First, the function to be called is pushed onto the stack
    /// * Then, the arguments to the call are pushed in direct order that is, the first argument is pushed first.
    /// * Finally you call `Lua.call()`
    /// * `args.args` is the number of arguments that you pushed onto the stack. When the function returns, all arguments and
    /// the function value are popped and the call results are pushed onto the stack.
    /// * The number of results is adjusted to `args.results`, unless `args.results` is `ziglua.mult_return`. In this case, all results from the function are pushed
    /// * Lua takes care that the returned values fit into the stack space, but it does not ensure any extra space in the stack. The function results
    /// are pushed onto the stack in direct order (the first result is pushed first), so that after the call the last result is
    /// on the top of the stack.
    ///
    /// Any error while calling and running the function is propagated upwards (with a longjmp).
    ///
    /// * Pops:   `(args.args+1)`
    /// * Pushes: `args.results`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_call
    pub fn call(lua: *Lua, args: CallArgs) void {
        switch (lang) {
            .lua51, .luajit, .luau => c.lua_call(@ptrCast(lua), args.args, args.results),
            else => c.lua_callk(@ptrCast(lua), args.args, args.results, 0, null),
        }
    }

    /// Continuations are supported in Lua 5.2, 5.3, and 5.4
    /// See https://www.lua.org/manual/5.4/manual.html#4.5
    pub const CallContArgs = struct {
        /// The number of args passed to the function from the stack
        args: i32 = 0,
        /// The number of results the function pushes to the stack upon returning
        results: i32 = 0,
        /// Context value passed to the continuation function
        ctx: switch (lang) {
            .lua52 => i32,
            .lua53, .lua54 => Context,
            else => void,
        },
        /// The continuation function
        k: switch (lang) {
            .lua52 => CFn,
            .lua53, .lua54 => CContFn,
            else => void,
        },
    };

    /// This function behaves exactly like `Lua.call()`, but allows the called function to yield
    ///
    /// Not implemented in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `(args.args + 1)`
    /// * Pushes: `args.results`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_callk
    pub fn callCont(lua: *Lua, args: CallContArgs) void {
        c.lua_callk(@ptrCast(lua), args.args, args.results, args.ctx, args.k);
    }

    /// Ensures that the stack has space for at least `n` extra elements, that is, that you can safely push up to `n` values into
    /// it. It returns an error if it cannot fulfill the request, either because it would cause the stack to be greater than a
    /// fixed maximum size (typically at least several thousand elements) or because it cannot allocate memory for the extra
    /// space. This function never shrinks the stack; if the stack already has space for the extra elements, it is left
    /// unchanged.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `memory` (Lua 5.1, LuaJIT, Luau)
    /// * Errors: `never` (Lua 5.2, 5.3, 5.4)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_checkstack
    pub fn checkStack(lua: *Lua, n: i32) !void {
        if (c.lua_checkstack(@ptrCast(lua), n) == 0) return error.LuaError;
    }

    /// Close the to-be-closed slot at the given index and set its value to nil. The index must be the last index previously
    /// marked to be closed (see `Lua.toClose()`) that is still active (that is, not closed yet).
    /// A `__close` metamethod cannot yield when called through this function.
    ///
    /// Only implemented in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_closeslot
    pub fn closeSlot(lua: *Lua, index: i32) void {
        c.lua_closeslot(@ptrCast(lua), index);
    }

    /// Resets a thread, cleaning its call stack and closing all pending to-be-closed variables. Returns an
    /// error status if an error occurs and leaves the error object on the top of the stack.
    ///
    /// The parameter `from` represents the coroutine that is resetting `lua`. If there is no such coroutine, this parameter can be
    /// `null`.
    ///
    /// Only implemented in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `?`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_closethread
    pub fn closeThread(lua: *Lua, from: ?*Lua) !void {
        if (c.lua_closethread(@ptrCast(lua), if (from) |f| @ptrCast(f) else null) != StatusCode.ok) return error.LuaError;
    }

    /// Compares two Lua values.
    ///
    /// Returns `true` if the value at index `index1` satisfies `op` when compared with the value at index
    /// `index2`, following the semantics of the corresponding Lua operator (that is, it may call metamethods). Otherwise returns
    /// `false`. Also returns `false` if any of the indices is not valid.
    ///
    /// Not implemented in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_compare
    pub fn compare(lua: *Lua, index1: i32, index2: i32, op: CompareOperator) bool {
        return c.lua_compare(@ptrCast(lua), index1, index2, @intFromEnum(op)) != 0;
    }

    /// Concatenates the `n` values at the top of the stack, pops them, and leaves the result at the top
    /// If the number of values is 1, the result is a single value on the stack (nothing changes)
    /// If the number of values is 0, the result is the empty string
    ///
    /// * Pops:   `n`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_concat
    pub fn concat(lua: *Lua, n: i32) void {
        c.lua_concat(@ptrCast(lua), n);
    }

    /// Calls the C function `c_fn` in protected mode. `c_fn` starts with only one element in its stack, a light userdata
    /// containing `userdata`. In case of errors, `Lua.cProtectedCall()` returns the same error codes as `Lua.protectedCall()`, plus the error object on the
    /// top of the stack; otherwise, it returns zero, and does not change the stack. All values returned by `c_fn` are discarded.
    ///
    /// Only implemented in Lua 5.1
    ///
    /// * Pops:   `0`
    /// * Pushes: `(0|1)`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.1/manual.html#lua_cpcall
    pub fn cProtectedCall(lua: *Lua, c_fn: CFn, userdata: *anyopaque) !void {
        const ret = c.lua_cpcall(@ptrCast(lua), c_fn, userdata);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_runtime => return error.LuaRuntime,
            StatusCode.err_memory => return error.OutOfMemory,
            StatusCode.err_error => return error.LuaMsgHandler,
            else => unreachable,
        }
    }

    /// Copies the element at index `from_index` into the valid index `to_index`, replacing the value at that position. Values at other
    /// positions are not affected.
    ///
    /// Not implemented in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_copy
    pub fn copy(lua: *Lua, from_index: i32, to_index: i32) void {
        c.lua_copy(@ptrCast(lua), from_index, to_index);
    }

    /// Creates a new empty table and pushes it onto the stack.
    ///
    /// Parameter `num_arr` is a hint for how many elements the table will
    /// have as a sequence; parameter `num_rec` is a hint for how many other elements the table will have. Lua may use these hints
    /// to preallocate memory for the new table. This preallocation may help performance when you know in advance how many
    /// elements the table will have. Otherwise you can use the function `Lua.newTable()`.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors `other` (Lua 5.2)
    /// * Errors: `memory` (other)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_createtable
    pub fn createTable(lua: *Lua, num_arr: i32, num_rec: i32) void {
        c.lua_createtable(@ptrCast(lua), num_arr, num_rec);
    }

    fn dump51(lua: *Lua, writer: CWriterFn, data: *anyopaque) !void {
        if (c.lua_dump(@ptrCast(lua), writer, data) != 0) return error.LuaError;
    }

    fn dump53(lua: *Lua, writer: CWriterFn, data: *anyopaque, strip: bool) !void {
        if (c.lua_dump(@ptrCast(lua), writer, data, @intFromBool(strip)) != 0) return error.LuaError;
    }

    /// Dumps a function as a binary chunk.
    ///
    /// Receives a Lua function on the top of the stack and produces a binary chunk that,
    /// if loaded again, results in a function equivalent to the one dumped. As it produces parts of the chunk, `Lua.dump()` calls
    /// function `writer` (see `CWriterFn`) with the given data to write them.
    ///
    /// For Lua 5.3 and 5.4:
    /// If `strip` is true, the binary representation may not include all debug information about the function, to save space.
    ///
    /// Returns an error code if the last call to the writer function fails
    ///
    /// This function does not pop the Lua function from the stack.
    ///
    /// Not implemented in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `memory` (Lua 5.1, LuaJIT)
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `never` (Lua 5.3, 5.4)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_dump
    pub const dump = switch (lang) {
        .lua53, .lua54 => dump53,
        else => dump51,
    };

    /// Returns `true` if the two values in acceptable indices `index1` and `index2` are equal, following the semantics of the Lua `==`
    /// operator (that is, may call metamethods). Otherwise returns `false`. Also returns `false` if any of the indices is non valid.
    ///
    /// Not implemented in Lua 5.2, 5.3, or 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.1/manual.html#lua_equal
    pub fn equal(lua: *Lua, index1: i32, index2: i32) bool {
        switch (lang) {
            .lua52, .lua53, .lua54 => @compileError("lua_equal is deprecated, use Lua.compare with .eq instead"),
            else => {},
        }
        return c.lua_equal(@ptrCast(lua), index1, index2) == 1;
    }

    /// Raises a Lua error, using the value on the top of the stack as the error object. This function does a long jump, and
    /// therefore never returns (see `Lua.raiseErrorStr()`).
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_error
    pub fn raiseError(lua: *Lua) noreturn {
        _ = c.lua_error(@ptrCast(lua));
        unreachable;
    }

    /// Perform a full garbage-collection cycle
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcCollect(lua: *Lua) void {
        _ = switch (lang) {
            .lua54 => c.lua_gc(@ptrCast(lua), c.LUA_GCCOLLECT),
            else => c.lua_gc(@ptrCast(lua), c.LUA_GCCOLLECT, 0),
        };
    }

    /// Stops the garbage collector
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcStop(lua: *Lua) void {
        _ = switch (lang) {
            .lua54 => c.lua_gc(@ptrCast(lua), c.LUA_GCSTOP),
            else => c.lua_gc(@ptrCast(lua), c.LUA_GCSTOP, 0),
        };
    }

    /// Restarts the garbage collector
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcRestart(lua: *Lua) void {
        _ = switch (lang) {
            .lua54 => c.lua_gc(@ptrCast(lua), c.LUA_GCRESTART),
            else => c.lua_gc(@ptrCast(lua), c.LUA_GCRESTART, 0),
        };
    }

    /// Performs an incremental step of garbage collection corresponding to the allocation of step_size Kbytes
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcStep(lua: *Lua, step_size: i32) void {
        _ = c.lua_gc(@ptrCast(lua), c.LUA_GCSTEP, step_size);
    }

    /// Returns the current amount of memory (in Kbytes) in use by Lua
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcCount(lua: *Lua) i32 {
        return switch (lang) {
            .lua54 => c.lua_gc(@ptrCast(lua), c.LUA_GCCOUNT),
            else => c.lua_gc(@ptrCast(lua), c.LUA_GCCOUNT, 0),
        };
    }

    /// Returns the remainder of dividing the current amount of bytes of memory in use by Lua by 1024
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcCountB(lua: *Lua) i32 {
        return switch (lang) {
            .lua54 => c.lua_gc(@ptrCast(lua), c.LUA_GCCOUNTB),
            else => c.lua_gc(@ptrCast(lua), c.LUA_GCCOUNTB, 0),
        };
    }

    /// Returns a boolean that tells whether the garbage collector is running
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcIsRunning(lua: *Lua) bool {
        return switch (lang) {
            .lua54 => c.lua_gc(@ptrCast(lua), c.LUA_GCISRUNNING) != 0,
            else => c.lua_gc(@ptrCast(lua), c.LUA_GCISRUNNING, 0) != 0,
        };
    }

    /// Changes the collector to incremental mode
    /// Returns true if the previous mode was generational
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub fn gcSetIncremental(lua: *Lua, pause: i32, step_mul: i32, step_size: i32) bool {
        return c.lua_gc(@ptrCast(lua), c.LUA_GCINC, pause, step_mul, step_size) == c.LUA_GCGEN;
    }

    fn gcSetGenerational52(lua: *Lua) void {
        _ = c.lua_gc(@ptrCast(lua), c.LUA_GCGEN, 0);
    }

    fn gcSetGenerational54(lua: *Lua, minor_mul: i32, major_mul: i32) bool {
        return c.lua_gc(@ptrCast(lua), c.LUA_GCGEN, minor_mul, major_mul) == c.LUA_GCINC;
    }

    pub fn gcSetGoal(lua: *Lua, goal: i32) i32 {
        return c.lua_gc(@ptrCast(lua), c.LUA_GCSETGOAL, goal);
    }

    pub fn gcSetStepSize(lua: *Lua, size: i32) i32 {
        return c.lua_gc(@ptrCast(lua), c.LUA_GCSETSTEPSIZE, size);
    }

    /// Changes the collector to generational mode
    /// Returns true if the previous mode was incremental
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gc
    pub const gcSetGenerational = switch (lang) {
        .lua52 => gcSetGenerational52,
        .lua54 => gcSetGenerational54,
        else => @compileError("gcSetGenerational() not available"),
    };

    /// Sets `pause` as the new value for the pause of the collector
    /// Returns the previous value of the pause
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcSetPause(lua: *Lua, pause: i32) i32 {
        return c.lua_gc(@ptrCast(lua), c.LUA_GCSETPAUSE, pause);
    }

    /// Sets `multiplier` as the new value for the step multiplier of the collector
    /// Returns the previous value of the step multiplier
    /// See https://www.lua.org/manual/5.3/manual.html#lua_gc
    pub fn gcSetStepMul(lua: *Lua, multiplier: i32) i32 {
        return c.lua_gc(@ptrCast(lua), c.LUA_GCSETSTEPMUL, multiplier);
    }

    /// Called by a continuation function to retrieve the status of the thread and context information
    ///
    /// * When called in the original function, `Lua.getContext()` returns `null`
    /// * When called inside a continuation function, `Lua.getContext()` returns the value of the context information
    /// (the value passed as the ctx argument to the callee together with the continuation function).
    /// * When the callee is `Lua.protectedCallCont()`, Lua may also call its continuation function to handle errors during the call. That is,
    /// upon an error in the function called by `Lua.protectedCallCont()`, Lua may not return to the original function but instead may call
    /// the continuation function. In that case, a call to `Lua.getContext()` will return an error (the value that would be
    /// returned by `Lua.protectedCallCont()`); the value of ctx will be set to the context information, as in the case of a yield.
    ///
    /// Only implemented in Lua 5.2
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#lua_getctx
    pub fn getContext(lua: *Lua) !?i32 {
        var ctx: i32 = undefined;
        const ret = c.lua_getctx(@ptrCast(lua), &ctx);
        switch (ret) {
            StatusCode.ok => return null,
            StatusCode.yield => return ctx,
            StatusCode.err_runtime => return error.LuaRuntime,
            StatusCode.err_memory => return error.OutOfMemory,
            StatusCode.err_error => return error.LuaMsgHandler,
            else => unreachable,
        }
    }

    /// Returns a slice of a raw memory area associated with the given Lua state.
    /// The application may use this area for any purpose; Lua does not use it for anything
    ///
    /// This area has a size of a pointer to void
    ///
    /// Only implemented in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getextraspace
    pub fn getExtraSpace(lua: *Lua) []u8 {
        return @as([*]u8, @ptrCast(c.lua_getextraspace(@as(*LuaState, @ptrCast(lua))).?))[0..@sizeOf(isize)];
    }

    /// Pushes onto the stack the environment table of the value at the given index.
    ///
    /// Only implemented in Lua 5.1 and Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.1/manual.html#lua_getfenv
    pub fn getFnEnvironment(lua: *Lua, index: i32) void {
        c.lua_getfenv(@ptrCast(lua), index);
    }

    /// Pushes onto the stack the value `t[key]`, where `t` is the value at the given `index`. As in Lua, this function may trigger a
    /// metamethod for the "index" event
    /// .
    /// Returns the type of the pushed value.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getfield
    pub fn getField(lua: *Lua, index: i32, key: [:0]const u8) LuaType {
        switch (lang) {
            .lua53, .lua54, .luau => return @enumFromInt(c.lua_getfield(@ptrCast(lua), index, key.ptr)),
            else => {
                c.lua_getfield(@ptrCast(lua), index, key.ptr);
                return lua.typeOf(-1);
            },
        }
    }

    /// Pushes onto the stack the value of the global name. Returns the type of that value.
    ///
    /// Returns an error if the global does not exist (is nil)
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getglobal
    pub fn getGlobal(lua: *Lua, name: [:0]const u8) !LuaType {
        const lua_type: LuaType = blk: {
            switch (lang) {
                .lua53, .lua54, .luau => break :blk @enumFromInt(c.lua_getglobal(@as(*LuaState, @ptrCast(lua)), name.ptr)),
                else => {
                    c.lua_getglobal(@as(*LuaState, @ptrCast(lua)), name.ptr);
                    break :blk lua.typeOf(-1);
                },
            }
        };

        if (lua_type == .nil) return error.LuaError;
        return lua_type;
    }

    /// Pushes onto the stack the value `t[i]` where `t` is the value at the given `index`
    /// As in Lua, this function may trigger a metamethod for the "index" event.
    ///
    /// Returns the type of the pushed value
    ///
    /// Only implemented in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_geti
    pub fn getIndex(lua: *Lua, index: i32, i: Integer) LuaType {
        return @enumFromInt(c.lua_geti(@ptrCast(lua), index, i));
    }

    pub fn getUserValue52(lua: *Lua, index: i32) void {
        c.lua_getuservalue(@ptrCast(lua), index);
    }

    // TODO: should all versions of getUserValue possibly fail?
    fn getUserValue53(lua: *Lua, index: i32) LuaType {
        return @enumFromInt(c.lua_getuservalue(@ptrCast(lua), index));
    }

    fn getUserValue54(lua: *Lua, index: i32, n: i32) !LuaType {
        const val_type: LuaType = @enumFromInt(c.lua_getiuservalue(@ptrCast(lua), index, n));
        if (val_type == .none) return error.LuaError;
        return val_type;
    }

    /// Pushes onto the stack the nth user value associated with the full userdata at the given index
    /// Returns the type of the pushed value or an error if the userdata does not have that value
    /// Pushes nil if the userdata does not have that value
    ///
    /// See https://www.lua.org/manual/5.3/manual.html#lua_getuservalue
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getiuservalue
    pub const getUserValue = switch (lang) {
        .lua53 => getUserValue53,
        .lua54 => getUserValue54,
        else => getUserValue52,
    };

    /// If the value at the given index has a metatable, the function pushes that metatable onto the stack
    /// Otherwise an error is returned
    ///
    /// * Pops:   `0`
    /// * Pushes: `(0|1)`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getmetatable
    pub fn getMetatable(lua: *Lua, index: i32) !void {
        if (c.lua_getmetatable(@ptrCast(lua), index) == 0) return error.LuaError;
    }

    /// Pushes onto the stack the value `t[k]`, where `t` is the value at the given `index` and `k` is the value on the top of the stack.
    /// This function pops the key from the stack, pushing the resulting value in its place. As in Lua, this function may
    /// trigger a metamethod for the "index" event.
    ///
    /// Returns the type of the pushed value.
    ///
    /// * Pops:   `1`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gettable
    pub fn getTable(lua: *Lua, index: i32) LuaType {
        switch (lang) {
            .lua53, .lua54, .luau => return @enumFromInt(c.lua_gettable(@ptrCast(lua), index)),
            else => {
                c.lua_gettable(@ptrCast(lua), index);
                return lua.typeOf(-1);
            },
        }
    }

    /// Returns the index of the top element in the stack. Because indices start at 1, this result is equal to the number of
    /// elements in the stack; in particular, 0 means an empty stack.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gettop
    pub fn getTop(lua: *Lua) i32 {
        return c.lua_gettop(@ptrCast(lua));
    }

    /// Only available in Luau
    pub fn setReadonly(lua: *Lua, idx: i32, enabled: bool) void {
        c.lua_setreadonly(@ptrCast(lua), idx, @intFromBool(enabled));
    }

    /// Only available in Luau
    pub fn getReadonly(lua: *Lua, idx: i32) bool {
        return c.lua_getreadonly(@ptrCast(lua), idx) != 0;
    }

    /// Moves the top element into the given valid `index`, shifting up the elements above this `index` to open space. Cannot be
    /// called with a pseudo-index, because a pseudo-index is not an actual stack position.
    ///
    /// * Pops:   `1`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_insert
    pub fn insert(lua: *Lua, index: i32) void {
        c.lua_insert(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is a boolean
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isboolean
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        return c.lua_isboolean(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is a CFn
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_iscfunction
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        return c.lua_iscfunction(@ptrCast(lua), index) != 0;
    }

    /// Returns true if the value at the given `index` is a function (C or Lua)
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isfunction
    pub fn isFunction(lua: *Lua, index: i32) bool {
        return c.lua_isfunction(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is an integer
    ///
    /// Only available in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isinteger
    pub fn isInteger(lua: *Lua, index: i32) bool {
        return c.lua_isinteger(@ptrCast(lua), index) != 0;
    }

    /// Returns true if the value at the given `index` is a light userdata
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_islightuserdata
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        return c.lua_islightuserdata(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is nil
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isnil
    pub fn isNil(lua: *Lua, index: i32) bool {
        return c.lua_isnil(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the given `index` is not valid
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isnone
    pub fn isNone(lua: *Lua, index: i32) bool {
        return c.lua_isnone(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the given `index` is not valid or if the value at the index is nil
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isnoneornil
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        return c.lua_isnoneornil(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is a number
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isnumber
    pub fn isNumber(lua: *Lua, index: i32) bool {
        return c.lua_isnumber(@ptrCast(lua), index) != 0;
    }

    /// Returns true if the value at the given `index` is a string or a number (which is always convertible to a string)
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isstring
    pub fn isString(lua: *Lua, index: i32) bool {
        return c.lua_isstring(@ptrCast(lua), index) != 0;
    }

    /// Returns true if the value at the given `index` is a table
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_istable
    pub fn isTable(lua: *Lua, index: i32) bool {
        return c.lua_istable(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is a thread
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isthread
    pub fn isThread(lua: *Lua, index: i32) bool {
        return c.lua_isthread(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the value at the given `index` is a userdata (either full or light)
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isuserdata
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        return c.lua_isuserdata(@ptrCast(lua), index) != 0;
    }

    /// Returns true if the value at the given `index` is a vector
    ///
    /// Only available in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    pub fn isVector(lua: *Lua, index: i32) bool {
        return c.lua_isvector(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Returns true if the given coroutine can yield
    ///
    /// Only available in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_isyieldable
    pub fn isYieldable(lua: *Lua) bool {
        return c.lua_isyieldable(@ptrCast(lua)) != 0;
    }

    /// Pushes the length of the value at the given `index` onto the stack
    /// Equivalent to the # operator in Lua and may
    /// trigger a metamethod for the "length" event. The result is pushed on the stack.
    ///
    /// Only implemented in Lua 5.2, 5.3, and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_len
    pub fn len(lua: *Lua, index: i32) void {
        c.lua_len(@ptrCast(lua), index);
    }

    /// Returns true if the value at `index1` is smaller than the value at `index2`, following the
    /// semantics of the Lua `<` operator (that is, may call metamethods). Also returns false if any of the
    /// indices is non valid.
    ///
    /// Only implemented in Lua 5.1, LuaJIT, and Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_lessthan
    pub fn lessThan(lua: *Lua, index1: i32, index2: i32) bool {
        return c.lua_lessthan(@ptrCast(lua), index1, index2) == 1;
    }

    fn load51(lua: *Lua, reader: CReaderFn, data: *anyopaque, chunk_name: [:0]const u8) !void {
        const ret = c.lua_load(@ptrCast(lua), reader, data, chunk_name.ptr);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.LuaSyntax,
            StatusCode.err_memory => return error.OutOfMemory,
            else => unreachable,
        }
    }

    fn load52(lua: *Lua, reader: CReaderFn, data: *anyopaque, chunk_name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        const ret = c.lua_load(@ptrCast(lua), reader, data, chunk_name.ptr, mode_str.ptr);

        return switch (lang) {
            .lua54 => switch (ret) {
                StatusCode.ok => {},
                StatusCode.err_syntax => error.LuaSyntax,
                StatusCode.err_memory => error.OutOfMemory,
                // lua_load runs pcall, so can also return any result of a pcall error
                StatusCode.err_runtime => error.LuaRuntime,
                StatusCode.err_error => error.LuaMsgHandler,
                else => unreachable,
            },
            else => switch (ret) {
                StatusCode.ok => {},
                StatusCode.err_syntax => error.LuaSyntax,
                StatusCode.err_memory => error.OutOfMemory,
                // lua_load runs pcall, so can also return any result of a pcall error
                StatusCode.err_runtime => error.LuaRuntime,
                StatusCode.err_error => error.LuaMsgHandler,
                StatusCode.err_gcmm => error.LuaGCMetaMethod,
                else => unreachable,
            },
        };
    }

    /// Loads a Lua chunk without running it
    /// If there are no errors, pushes the compiled chunk on the top of the stack as a function
    /// See https://www.lua.org/manual/5.4/manual.html#lua_load
    pub const load = switch (lang) {
        .lua51, .luajit => load51,
        else => load52,
    };

    /// Creates a new empty table and pushes it onto the stack
    /// Equivalent to `Lua.createTable(0, 0)`
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `memory` (All other versions)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_newtable
    pub fn newTable(lua: *Lua) void {
        c.lua_newtable(@as(*LuaState, @ptrCast(lua)));
    }

    /// Creates a new thread, pushes it on the stack, and returns a Lua state that represents the new thread
    /// The new thread shares the global environment but has a separate execution stack
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `memory` (All other versions)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_newthread
    pub fn newThread(lua: *Lua) *Lua {
        return @ptrCast(c.lua_newthread(@ptrCast(lua)).?);
    }

    /// This function allocates a new userdata of the given type.
    /// Returns a pointer to the Lua-owned data
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newuserdata
    fn newUserdata51(lua: *Lua, comptime T: type) *T {
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdata(@as(*LuaState, @ptrCast(lua)), @sizeOf(T)).?;
        return @ptrCast(@alignCast(ptr));
    }

    /// This function allocates a new userdata of the given type with user_values associated Lua values.
    /// Returns a pointer to the Lua-owned data
    /// See https://www.lua.org/manual/5.4/manual.html#lua_newuserdatauv
    fn newUserdata54(lua: *Lua, comptime T: type, user_values: i32) *T {
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdatauv(@ptrCast(lua), @sizeOf(T), user_values).?;
        return @ptrCast(@alignCast(ptr));
    }

    pub const newUserdata = switch (lang) {
        .lua54 => newUserdata54,
        else => newUserdata51,
    };

    /// This function creates and pushes a slice of full userdata onto the stack.
    /// Returns a slice to the Lua-owned data.
    /// See https://www.lua.org/manual/5.3/manual.html#lua_newuserdata
    fn newUserdataSlice51(lua: *Lua, comptime T: type, size: usize) []T {
        // safe to .? because this function throws a Lua error on out of memory
        const ptr = c.lua_newuserdata(@as(*LuaState, @ptrCast(lua)), @sizeOf(T) * size).?;
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    /// This function creates and pushes a slice of full userdata onto the stack with user_values associated Lua values.
    /// Returns a slice to the Lua-owned data.
    /// See https://www.lua.org/manual/5.4/manual.html#lua_newuserdatauv
    fn newUserdataSlice54(lua: *Lua, comptime T: type, size: usize, user_values: i32) []T {
        // safe to .? because this function throws a Lua error on out of memory
        const ptr = c.lua_newuserdatauv(@ptrCast(lua), @sizeOf(T) * size, user_values).?;
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    pub const newUserdataSlice = switch (lang) {
        .lua54 => newUserdataSlice54,
        else => newUserdataSlice51,
    };

    pub fn newUserdataTagged(lua: *Lua, comptime T: type, tag: i32) *T {
        const UTAG_PROXY = c.LUA_UTAG_LIMIT + 1; // not exposed in headers
        std.debug.assert((tag >= 0 and tag < c.LUA_UTAG_LIMIT) or tag == UTAG_PROXY); // Luau will do the same assert, this is easier to debug
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdatatagged(@ptrCast(lua), @sizeOf(T), tag).?;
        return @ptrCast(@alignCast(ptr));
    }

    /// Returns the tag of a userdata at the given index
    /// TODO: rename to getUserdataTag?
    pub fn userdataTag(lua: *Lua, index: i32) !i32 {
        const tag = c.lua_userdatatag(@ptrCast(lua), index);
        if (tag == -1) return error.LuaError;
        return tag;
    }

    /// This function allocates a new userdata of the given type with an associated
    /// destructor callback.
    ///
    /// Returns a pointer to the Lua-owned data
    ///
    /// Note: Luau doesn't support the usual Lua __gc metatable destructor.  Use this instead.
    pub fn newUserdataDtor(lua: *Lua, comptime T: type, dtor_fn: CUserdataDtorFn) *T {
        // safe to .? because this function throws a Lua error on out of memory
        // so the returned pointer should never be null
        const ptr = c.lua_newuserdatadtor(@ptrCast(lua), @sizeOf(T), @ptrCast(dtor_fn)).?;
        return @ptrCast(@alignCast(ptr));
    }

    /// Pops a key from the stack, and pushes a key–value pair from the table at the given `index`, the "next" pair after the
    /// given key. If there are no more elements in the table, then lua_next returns 0 and pushes nothing.
    ///
    /// While traversing a table, avoid calling `Lua.toString()` directly on a key, unless you know that the key is actually a
    /// string. Recall that `Lua.toString()` may change the value at the given `index`; this confuses the next call to `Lua.next()`.
    /// This function may raise an error if the given key is neither nil nor present in the table. See the Lua function `next()` for the
    /// caveats of modifying the table during its traversal.
    ///
    /// * Pops:   `1`
    /// * Pushes: `(2|0)`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_next
    pub fn next(lua: *Lua, index: i32) bool {
        return c.lua_next(@ptrCast(lua), index) != 0;
    }

    /// Tries to convert a Lua float to a Lua integer; the float `n` must have an integral value. If that value is within the range of Lua integers, it is converted to an integer and assigned to *p. The macro results in a boolean indicating whether the conversion was successful. (Note that this range test can be tricky to do correctly without this macro, due to rounding.)
    ///
    /// Only available in Lua 5.4
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_numbertointeger
    pub fn numberToInteger(n: Number) !Integer {
        // translate-c failure
        // return c.lua_numbertointeger(n, i) != 0;
        const min_float: Number = @floatFromInt(min_integer);
        if (n >= min_float and n < -min_float) {
            return @intFromFloat(n);
        } else return error.LuaError;
    }

    /// Returns the "length" of the value at the given acceptable `index`:
    /// * for strings, this is the string length
    /// * for tables, this is the result of the length operator ('#')
    /// * for userdata, this is the size of the block of memory allocated for the userdata
    /// * for other values, it is 0.
    ///
    /// Only implemented in Lua 5.1, LuaJIT, and Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.1/manual.html#lua_objlen
    pub fn objectLen(lua: *Lua, index: i32) switch (lang) {
        .luau => i32,
        else => usize,
    } {
        return c.lua_objlen(@ptrCast(lua), index);
    }

    pub const ProtectedCallArgs = struct {
        /// The number of args passed to the function from the stack
        args: i32 = 0,
        /// The number of results the function pushes to the stack upon returning
        results: i32 = 0,
        /// The stack index of a message handler (known as errfunc in some versions of Lua)
        msg_handler: i32 = 0,
    };

    /// Calls a function (or a callable object) in protected mode.
    /// Both `args.args` and `args.results` have the same meaning as in `Lua.call()`. If there are no errors during the call, `Lua.protectedCall()` behaves
    /// exactly like `Lua.call()`. However, if there is any error, `Lua.protectedCall()` catches it, pushes a single value on the stack (the
    /// error object), and returns an error code. Like `Lua.call()`, `Lua.protectedCall()` always removes the function and its arguments from
    /// the stack.
    ///
    /// If `args.msg_handler` is 0, then the error object returned on the stack is exactly the original error object. Otherwise, `args.msg_handler` is the
    /// stack index of a message handler. (This index cannot be a pseudo-index.) In case of runtime errors, this handler will
    /// be called with the error object and its return value will be the object returned on the stack by `Lua.protectedCall()`.
    /// Typically, the message handler is used to add more debug information to the error object, such as a stack traceback.
    /// Such information cannot be gathered after the return of `Lua.protectedCall()`, since by then the stack has unwound.
    ///
    /// * Pops:   `(args.args + 1)`
    /// * Pushes: `(args.results|1)`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pcallk
    pub fn protectedCall(lua: *Lua, args: ProtectedCallArgs) !void {
        const ret = switch (lang) {
            .lua51, .luajit, .luau => c.lua_pcall(@ptrCast(lua), args.args, args.results, args.msg_handler),
            else => c.lua_pcallk(@ptrCast(lua), args.args, args.results, args.msg_handler, 0, null),
        };

        return switch (lang) {
            .lua54 => switch (ret) {
                StatusCode.ok => return,
                StatusCode.err_runtime => return error.LuaRuntime,
                StatusCode.err_memory => return error.OutOfMemory,
                StatusCode.err_error => return error.LuaMsgHandler,
                else => unreachable,
            },
            .lua52, .lua53 => switch (ret) {
                StatusCode.ok => return,
                StatusCode.err_runtime => return error.LuaRuntime,
                StatusCode.err_memory => return error.OutOfMemory,
                StatusCode.err_error => return error.LuaMsgHandler,
                StatusCode.err_gcmm => return error.LuaGCMetaMethod,
                else => unreachable,
            },
            else => switch (ret) {
                StatusCode.ok => return,
                StatusCode.err_runtime => return error.LuaRuntime,
                StatusCode.err_memory => return error.OutOfMemory,
                StatusCode.err_error => return error.LuaMsgHandler,
                else => unreachable,
            },
        };
    }

    pub const ProtectedCallContArgs = struct {
        /// The number of args passed to the function from the stack
        args: i32 = 0,
        /// The number of results the function pushes to the stack upon returning
        results: i32 = 0,
        /// The stack index of a message handler (known as errfunc in some versions of Lua)
        msg_handler: i32 = 0,
        /// Context value passed to the continuation function
        ctx: switch (lang) {
            .lua52 => i32,
            .lua53, .lua54 => Context,
            else => void,
        },
        /// The continuation function
        k: switch (lang) {
            .lua52 => CFn,
            .lua53, .lua54 => CContFn,
            else => void,
        },
    };

    /// This function behaves exactly like `Lua.protectedCall()`, except that it allows the called function to yield
    ///
    /// * Pops:   `(nargs + 1)`
    /// * Pushes: `(nresults|1)`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pcallk
    pub fn protectedCallCont(lua: *Lua, args: ProtectedCallContArgs) !void {
        const ret = switch (lang) {
            .lua51, .luajit, .luau => c.lua_pcall(@ptrCast(lua), args.args, args.results, args.msg_handler),
            else => c.lua_pcallk(@ptrCast(lua), args.args, args.results, args.msg_handler, 0, null),
        };

        return switch (lang) {
            .lua54 => switch (ret) {
                StatusCode.ok => return,
                StatusCode.err_runtime => return error.LuaRuntime,
                StatusCode.err_memory => return error.OutOfMemory,
                StatusCode.err_error => return error.LuaMsgHandler,
                else => unreachable,
            },
            .lua52, .lua53 => switch (ret) {
                StatusCode.ok => return,
                StatusCode.err_runtime => return error.LuaRuntime,
                StatusCode.err_memory => return error.OutOfMemory,
                StatusCode.err_error => return error.LuaMsgHandler,
                StatusCode.err_gcmm => return error.LuaGCMetaMethod,
                else => unreachable,
            },
            else => @compileError("Only implemented in Lua 5.2, 5.3, and 5.4"),
        };
    }

    /// Pops `n` elements from the top of the stack
    ///
    /// * Pops:   `n`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pop
    pub fn pop(lua: *Lua, n: i32) void {
        lua.setTop(-n - 1);
    }

    /// Pushes a boolean value with value `b` onto the stack
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushboolean
    pub fn pushBoolean(lua: *Lua, b: bool) void {
        c.lua_pushboolean(@ptrCast(lua), @intFromBool(b));
    }

    /// Pushes a new C closure onto the stack. This function receives a pointer to a C function and pushes onto the stack a Lua
    /// value of type function that, when called, invokes the corresponding C function. The parameter `n` tells how many upvalues
    /// this function will have.
    ///
    /// Any function to be callable by Lua must follow the correct protocol to receive its parameters and return its results.
    ///
    ///
    /// When a C function is created, it is possible to associate some values with it, the so called upvalues; these upvalues
    /// are then accessible to the function whenever it is called. This association is called a C closure. To create
    /// a C closure, first the initial values for its upvalues must be pushed onto the stack. (When there are multiple
    /// upvalues, the first value is pushed first.) Then `Lua.pushClosure()` is called to create and push the C function onto the
    /// stack, with the argument `n` telling how many values will be associated with the function. `Lua.pushClosure()` also pops
    /// these values from the stack.
    /// The maximum value for `n` is 255.
    ///
    /// When `n` is zero, this function creates a light C function, which is just a pointer to the C function. In that case, it
    /// never raises a memory error.
    ///
    /// * Pops:   `n`
    /// * Pushes: `1`
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `memory` (All other versions)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushcclosure
    pub fn pushClosure(lua: *Lua, c_fn: CFn, n: i32) void {
        switch (lang) {
            .luau => c.lua_pushcclosurek(@ptrCast(lua), c_fn, "ZigFn", n, null),
            else => c.lua_pushcclosure(@ptrCast(lua), c_fn, n),
        }
    }

    /// Pushes a new Closure onto the stack with a debugname. See `Lua.pushClosure()` for full details.
    ///
    /// Only available in Luau
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushcclosure
    pub fn pushClosureNamed(lua: *Lua, c_fn: CFn, debugname: [:0]const u8, n: i32) void {
        c.lua_pushcclosurek(@ptrCast(lua), c_fn, debugname, n, null);
    }

    /// Pushes a new function onto the stack. Equivalent to `Lua.pushClosure()` with no upvalues.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushcfunction
    pub fn pushFunction(lua: *Lua, c_fn: CFn) void {
        switch (lang) {
            .luau => c.lua_pushcclosurek(@ptrCast(lua), c_fn, "ZigFn", 0, null),
            else => c.lua_pushcfunction(@as(*LuaState, @ptrCast(lua)), c_fn),
        }
    }

    /// Pushes a new function onto the stack with a debugname. See `Lua.pushFunction()` for full details.
    ///
    /// Only available in Luau
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushcfunction
    pub fn pushFunctionNamed(lua: *Lua, c_fn: CFn, debugname: [:0]const u8) void {
        c.lua_pushcclosurek(@ptrCast(lua), c_fn, debugname, 0, null);
    }

    /// Pushes onto the stack a formatted string and returns a pointer to this string. It is similar to the ISO C
    /// function `sprintf`, but has two important differences. First, you do not have to allocate space for the result; the
    /// result is a Lua string and Lua takes care of memory allocation (and deallocation, through garbage collection). Second,
    /// the conversion specifiers are quite restricted. There are no flags, widths, or precisions. The conversion specifiers
    /// can only be:
    /// * `%%` inserts the character `%`
    /// * `%s` inserts a zero-terminated string, with no size restrictions
    /// * `%f` inserts a lua_Number
    /// * `%I` inserts a lua_Integer (Only in Lua 5.3 and 5.4)
    /// * `%p` inserts a pointer
    /// * `%d` inserts an int
    /// * `%c` inserts an int as a one-byte character
    /// * `%U` inserts a long int as a UTF-8 byte sequence (Only in Lua 5.3 and 5.4)
    ///
    /// This function may raise errors due to memory overflow or an invalid conversion specifier.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushfstring
    pub fn pushFString(lua: *Lua, fmt: [:0]const u8, args: anytype) [:0]const u8 {
        const ptr = @call(
            .auto,
            if (lang == .luau) c.lua_pushfstringL else c.lua_pushfstring,
            .{ @as(*LuaState, @ptrCast(lua)), fmt.ptr } ++ args,
        );
        const l = lua.rawLen(-1);
        return ptr[0..l :0];
    }

    /// Pushes the global environment onto the stack
    ///
    /// Only implemented in Lua 5.2, 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushglobaltable
    pub fn pushGlobalTable(lua: *Lua) void {
        // lua_pushglobaltable is a macro and c-translate assumes it returns opaque
        // so just reimplement the macro here
        // c.lua_pushglobaltable(@ptrCast(lua));
        _ = lua.rawGetIndex(registry_index, ridx_globals);
    }

    /// Pushes an integer with value `n` onto the stack
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushinteger
    pub fn pushInteger(lua: *Lua, n: Integer) void {
        c.lua_pushinteger(@ptrCast(lua), n);
    }

    /// Pushes a light userdata onto the stack.
    ///
    /// Userdata represent C values in Lua. A light userdata represents a pointer, an `*anyopaque`. It is a value (like a number): you
    /// do not create it, it has no individual metatable, and it is not collected (as it was never created). A light userdata
    /// is equal to "any" light userdata with the same memory address.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushlightuserdata
    pub fn pushLightUserdata(lua: *Lua, ptr: *anyopaque) void {
        c.lua_pushlightuserdata(@as(*LuaState, @ptrCast(lua)), ptr);
    }

    /// Pushes the string pointed to by `str` onto the stack. Lua will make or reuse an internal copy of the given
    /// string, so the memory at `str` can be freed or reused immediately after the function returns. The string can contain any
    /// binary data, including embedded zeros.
    ///
    /// Returns a slice that points to the internal Lua copy of the string
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `memory` (All other versions)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushlstring
    pub fn pushString(lua: *Lua, str: []const u8) [:0]const u8 {
        switch (lang) {
            .lua51, .luajit, .luau => {
                c.lua_pushlstring(@ptrCast(lua), str.ptr, str.len);
                return lua.toString(-1) catch unreachable;
            },
            else => return c.lua_pushlstring(@ptrCast(lua), str.ptr, str.len)[0..str.len :0],
        }
    }

    /// Pushes a nil value onto the stack
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushnil
    pub fn pushNil(lua: *Lua) void {
        c.lua_pushnil(@ptrCast(lua));
    }

    /// Pushes a float with value `n` onto the stack
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushnumber
    pub fn pushNumber(lua: *Lua, n: Number) void {
        c.lua_pushnumber(@ptrCast(lua), n);
    }

    /// Pushes the zero-terminated string pointed to by `str` onto the stack. Lua will make or reuse an internal copy of the given
    /// string, so the memory at `str` can be freed or reused immediately after the function returns.
    ///
    /// Returns a slice that points to the internal Lua copy of the string.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `memory` (All other versions)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushstring
    pub fn pushStringZ(lua: *Lua, str: [:0]const u8) [:0]const u8 {
        switch (lang) {
            .lua51, .luajit, .luau => {
                c.lua_pushstring(@ptrCast(lua), str.ptr);
                return lua.toString(-1) catch unreachable;
            },
            else => return c.lua_pushstring(@ptrCast(lua), str.ptr)[0..str.len :0],
        }
    }

    /// Pushes the thread represented by `lua` onto the stack. Returns true if this thread is the main thread of its state.
    ///
    /// Can be called as `Lua.pushThread(thread) to push another thread's state.`
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushthread
    pub fn pushThread(lua: *Lua) bool {
        return c.lua_pushthread(@ptrCast(lua)) != 0;
    }

    /// Pushes a number with value `n` onto the stack
    ///
    /// Only available in Lua 5.2
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#lua_pushunsigned
    pub fn pushUnsigned(lua: *Lua, n: Unsigned) void {
        return c.lua_pushunsigned(@ptrCast(lua), n);
    }

    /// Pushes a copy of the element at the given index onto the stack
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_pushvalue
    pub fn pushValue(lua: *Lua, index: i32) void {
        c.lua_pushvalue(@ptrCast(lua), index);
    }

    fn pushVector3(lua: *Lua, x: f32, y: f32, z: f32) void {
        c.lua_pushvector(@ptrCast(lua), x, y, z);
    }

    fn pushVector4(lua: *Lua, x: f32, y: f32, z: f32, w: f32) void {
        c.lua_pushvector(@ptrCast(lua), x, y, z, w);
    }

    /// Pushes a floating point 3-vector (or 4-vector if configured) `v` onto the stack
    ///
    /// Only available in Luau
    pub const pushVector = if (luau_vector_size == 3) pushVector3 else pushVector4;

    /// Returns true if the two values in indices `index1` and `index2` are primitively equal
    /// (that is, equal without calling the `__eq` metamethod). Otherwise returns false.
    /// Also returns false if any of the indices are not valid.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawequal
    /// TODO: should this be rename to equalRaw?
    pub fn rawEqual(lua: *Lua, index1: i32, index2: i32) bool {
        return c.lua_rawequal(@ptrCast(lua), index1, index2) != 0;
    }

    /// Similar to `Lua.getTable()` but does a raw access (without metamethods).
    ///
    /// Returns the type of the pushed value.
    ///
    /// * Pops:   `1`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawget
    /// TODO: should this be renamed to getTableRaw (seems more logical)?
    pub fn rawGetTable(lua: *Lua, index: i32) LuaType {
        switch (lang) {
            .lua53, .lua54, .luau => return @enumFromInt(c.lua_rawget(@ptrCast(lua), index)),
            else => {
                c.lua_rawget(@ptrCast(lua), index);
                return lua.typeOf(-1);
            },
        }
    }

    const RawGetIndexNType = switch (lang) {
        .lua51, .lua52, .luajit, .luau => i32,
        else => Integer,
    };

    /// Pushes onto the stack the value t[n], where `t` is the table at the given `index`
    /// The access is raw, that is, it does not use the `__index` metavalue.
    ///
    /// Returns the `LuaType` of the pushed value
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawgeti
    pub fn rawGetIndex(lua: *Lua, index: i32, n: RawGetIndexNType) LuaType {
        switch (lang) {
            .lua53, .lua54, .luau => return @enumFromInt(c.lua_rawgeti(@ptrCast(lua), index, n)),
            else => {
                c.lua_rawgeti(@ptrCast(lua), index, n);
                return lua.typeOf(-1);
            },
        }
    }

    /// Pushes onto the stack the value `t[k]`, where `t` is the table at the given `index` and `k` is the pointer `p` represented as a
    /// light userdata.
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawgetp
    pub fn rawGetPtr(lua: *Lua, index: i32, p: *const anyopaque) LuaType {
        switch (lang) {
            .lua53, .lua54 => return @enumFromInt(c.lua_rawgetp(@ptrCast(lua), index, p)),
            else => {
                c.lua_rawgetp(@ptrCast(lua), index, p);
                return lua.typeOf(-1);
            },
        }
    }

    /// Returns the raw "length" of the value at the given index:
    /// * for strings, this is the string length
    /// * for tables, this is the result of the length operator ('#') with no metamethods
    /// * for userdata, this is the size of the block of memory allocated for the userdata
    /// * For other values, this call returns 0.
    ///
    /// Not available in Lua 5.1, LuaJIT or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawlen
    pub fn rawLen(lua: *Lua, index: i32) usize {
        switch (lang) {
            .lua51, .luau, .luajit => return @intCast(c.lua_objlen(@ptrCast(lua), index)),
            else => return @intCast(c.lua_rawlen(@ptrCast(lua), index)),
        }
    }

    /// Similar to `Lua.setTable()` but does a raw assignment (without metamethods)
    ///
    /// * Pops:   `2`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawset
    pub fn rawSetTable(lua: *Lua, index: i32) void {
        c.lua_rawset(@ptrCast(lua), index);
    }

    const RawSetIndexIType = switch (lang) {
        .lua51, .lua52, .luajit, .luau => i32,
        else => Integer,
    };

    /// Does the equivalent of `t[i] = v`, where `t` is the table at the given `index` and `v` is the value on the top of the stack.
    /// This function pops the value from the stack. The assignment is raw, that is, it does not use the `__newindex` metavalue.
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawseti
    pub fn rawSetIndex(lua: *Lua, index: i32, i: RawSetIndexIType) void {
        c.lua_rawseti(@ptrCast(lua), index, i);
    }

    /// Does the equivalent of `t[p] = v`, where `t` is the table at the given `index`, `p` is encoded as a light userdata, and `v` is
    /// the value on the top of the stack.
    ///
    /// This function pops the value from the stack. The assignment is raw, that is, it does not use the `__newindex` metavalue.
    ///
    /// Not available in Lua 5.1, LuaJIT or Luau
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rawsetp
    pub fn rawSetPtr(lua: *Lua, index: i32, p: *const anyopaque) void {
        c.lua_rawsetp(@ptrCast(lua), index, p);
    }

    /// Sets the C function `f` as the new value of global `name`
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_register
    pub fn register(lua: *Lua, name: [:0]const u8, f: CFn) void {
        switch (lang) {
            .luau => {
                lua.pushFunction(f);
                lua.setGlobal(name);
            },
            else => c.lua_register(@as(*LuaState, @ptrCast(lua)), name.ptr, f),
        }
    }

    /// Removes the element at the given valid `index` shifting down elements to fill the gap.
    /// This function cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_remove
    pub fn remove(lua: *Lua, index: i32) void {
        c.lua_remove(@as(*LuaState, @ptrCast(lua)), index);
    }

    /// Moves the top element into the given valid `index` without shifting any elements,
    /// then pops the top element
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_replace
    pub fn replace(lua: *Lua, index: i32) void {
        c.lua_replace(@as(*LuaState, @ptrCast(lua)), index);
    }

    pub fn resumeThread51(lua: *Lua, num_args: i32) !ResumeStatus {
        const thread_status = c.lua_resume(@ptrCast(lua), num_args);
        switch (thread_status) {
            StatusCode.err_runtime => return error.LuaRuntime,
            StatusCode.err_memory => return error.OutOfMemory,
            StatusCode.err_error => return error.LuaMsgHandler,
            else => return @enumFromInt(thread_status),
        }
    }

    /// Starts and resumes a coroutine in the given thread
    /// See https://www.lua.org/manual/5.3/manual.html#lua_resume
    fn resumeThread52(lua: *Lua, from: ?*Lua, num_args: i32) !ResumeStatus {
        const from_state: ?*LuaState = if (from) |from_val| @ptrCast(from_val) else null;
        const thread_status = c.lua_resume(@ptrCast(lua), from_state, num_args);
        switch (thread_status) {
            StatusCode.err_runtime => return error.LuaRuntime,
            StatusCode.err_memory => return error.OutOfMemory,
            StatusCode.err_error => return error.LuaMsgHandler,
            StatusCode.err_gcmm => return error.LuaGCMetaMethod,
            else => return @enumFromInt(thread_status),
        }
    }

    /// Starts and resumes a coroutine in the given thread
    /// See https://www.lua.org/manual/5.4/manual.html#lua_resume
    fn resumeThread54(lua: *Lua, from: ?*Lua, num_args: i32, num_results: *i32) !ResumeStatus {
        const from_state: ?*LuaState = if (from) |from_val| @ptrCast(from_val) else null;
        const thread_status = c.lua_resume(@ptrCast(lua), from_state, num_args, num_results);
        switch (thread_status) {
            StatusCode.err_runtime => return error.LuaRuntime,
            StatusCode.err_memory => return error.OutOfMemory,
            StatusCode.err_error => return error.LuaMsgHandler,
            else => return @enumFromInt(thread_status),
        }
    }

    pub fn resumeThreadLuau(lua: *Lua, from: ?*Lua, num_args: i32) !ResumeStatus {
        const from_state: ?*LuaState = if (from) |from_val| @ptrCast(from_val) else null;
        const thread_status = c.lua_resume(@ptrCast(lua), from_state, num_args);
        switch (thread_status) {
            StatusCode.err_runtime => return error.LuaRuntime,
            StatusCode.err_memory => return error.OutOfMemory,
            StatusCode.err_error => return error.LuaMsgHandler,
            else => return @enumFromInt(thread_status),
        }
    }

    pub const resumeThread = switch (lang) {
        .lua51, .luajit => resumeThread51,
        .lua52, .lua53 => resumeThread52,
        .lua54 => resumeThread54,
        .luau => resumeThreadLuau,
    };

    /// Rotates the stack elements between the valid index `index` and the top of the stack. The elements are rotated `n` positions
    /// in the direction of the top, for a positive `n`, or `-n` positions in the direction of the bottom, for a negative `n`. The
    /// absolute value of `n` must not be greater than the size of the slice being rotated. This function cannot be called with a
    /// pseudo-index, because a pseudo-index is not an actual stack position.
    ///
    /// Only available in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_rotate
    pub fn rotate(lua: *Lua, index: i32, n: i32) void {
        c.lua_rotate(@ptrCast(lua), index, n);
    }

    /// Pops a table from the stack and sets it as the new environment for the value at the
    /// given `index`. Returns an error if the value at that index is not a function or thread or userdata.
    ///
    /// Only implemented in Lua 5.1 and Luau
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.1/manual.html#lua_setfenv
    pub fn setFnEnvironment(lua: *Lua, index: i32) !void {
        if (c.lua_setfenv(@ptrCast(lua), index) == 0) return error.LuaError;
    }

    /// Does the equivalent to `t[k] = v` where `t` is the value at the given `index`
    /// and `v` is the value on the top of the stack
    ///
    /// This function pops the value from the stack. As in Lua, this function may trigger a metamethod for the `__newindex` event
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setfield
    pub fn setField(lua: *Lua, index: i32, k: [:0]const u8) void {
        c.lua_setfield(@ptrCast(lua), index, k.ptr);
    }

    /// Pops a value from the stack and sets it as the new value of global `name`
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setglobal
    pub fn setGlobal(lua: *Lua, name: [:0]const u8) void {
        c.lua_setglobal(@as(*LuaState, @ptrCast(lua)), name.ptr);
    }

    /// Does the equivalent to `t[n] = v` where `t` is the value at the given `index`
    /// and `v` is the value on the top of the stack. Pops the value from the stack
    ///
    /// As in Lua, this function may trigger a metamethod for the `__newindex` event
    ///
    /// Only implemented in Lua 5.3 and 5.4
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_seti
    pub fn setIndex(lua: *Lua, index: i32, n: Integer) void {
        c.lua_seti(@ptrCast(lua), index, n);
    }

    /// Pops a value from the stack and sets it as the user value associated to
    /// the full userdata at the given index
    /// Returns an error if the userdata does not have that value
    /// See https://www.lua.org/manual/5.3/manual.html#lua_setuservalue
    fn setUserValue52(lua: *Lua, index: i32) !void {
        c.lua_setuservalue(@ptrCast(lua), index);
    }

    /// Pops a value from the stack and sets it as the new `n`th user value associated to
    /// the full userdata at the given index
    /// Returns an error if the userdata does not have that value
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setiuservalue
    fn setUserValue54(lua: *Lua, index: i32, n: i32) !void {
        if (c.lua_setiuservalue(@ptrCast(lua), index, n) == 0) return error.LuaError;
    }

    pub const setUserValue = switch (lang) {
        .lua54 => setUserValue54,
        else => setUserValue52,
    };

    /// Pops a table or nil from the stack and sets that value as the new metatable for the
    /// value at the given `index`
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setmetatable
    pub fn setMetatable(lua: *Lua, index: i32) void {
        // lua_setmetatable always returns 1 so is safe to ignore
        _ = c.lua_setmetatable(@ptrCast(lua), index);
    }

    /// Does the equivalent to `t[k] = v`, where `t` is the value at the given `index`, `v` is the value on the top of the stack, and `k`
    /// is the value just below the top.
    ///
    /// This function pops both the key and the value from the stack. As in Lua, this function may trigger a metamethod for the
    /// `__newindex` event
    ///
    /// * Pops:   `2`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_settable
    pub fn setTable(lua: *Lua, index: i32) void {
        c.lua_settable(@ptrCast(lua), index);
    }

    /// Accepts any `index`, or 0, and sets the stack top to this `index`. If the new top is greater than the old one, then the new
    /// elements are filled with nil. If index is 0, then all stack elements are removed.
    ///
    /// In Lua 5.4 this function can run arbitrary code when removing an index marked as to-be-closed from the stack.
    ///
    /// * Pops:   `?`
    /// * Pushes: `?`
    /// * Errors: `never`
    /// * Errors: `other` (Lua 5.4)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_settop
    pub fn setTop(lua: *Lua, index: i32) void {
        c.lua_settop(@ptrCast(lua), index);
    }

    /// Set userdata tag at the given index
    ///
    /// Only available in Luau
    pub fn setUserdataTag(lua: *Lua, index: i32, tag: i32) void {
        std.debug.assert((tag >= 0 and tag < c.LUA_UTAG_LIMIT)); // Luau will do the same assert, this is easier to debug
        c.lua_setuserdatatag(@ptrCast(lua), index, tag);
    }

    /// Sets the warning function to be used by Lua to emit warnings
    /// The `data` parameter sets the value `data` passed to the warning function
    ///
    /// Only available in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setwarnf
    pub fn setWarnF(lua: *Lua, warn_fn: CWarnFn, data: ?*anyopaque) void {
        c.lua_setwarnf(@ptrCast(lua), warn_fn, data);
    }

    /// Returns the status of this thread
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_status
    pub fn status(lua: *Lua) Status {
        return @enumFromInt(c.lua_status(@ptrCast(lua)));
    }

    /// Converts the zero-terminated string `str` to a number, pushes that number onto the stack,
    /// Returns an error if conversion failed
    ///
    /// Only available in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_stringtonumber
    pub fn stringToNumber(lua: *Lua, str: [:0]const u8) !void {
        const size = c.lua_stringtonumber(@ptrCast(lua), str.ptr);
        if (size == 0) return error.LuaError;
    }

    /// Converts the Lua value at the given index to a Zig boolean value. Like all tests in Lua, `Lua.toBoolean()` returns
    /// true for any Lua value different from false and nil; otherwise it returns false. (If you want to accept only actual
    /// boolean values, use `Lua.isBoolean()` to test the value's type.)
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_toboolean
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        return c.lua_toboolean(@ptrCast(lua), index) != 0;
    }

    /// Converts a value at the given `index` into a CFn
    /// Returns an error if the value is not a CFn
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_tocfunction
    pub fn toCFunction(lua: *Lua, index: i32) !CFn {
        return c.lua_tocfunction(@ptrCast(lua), index) orelse return error.LuaError;
    }

    /// Marks the given index in the stack as a to-be-closed slot
    ///
    /// Like a to-be-closed variable in Lua, the value
    /// at that slot in the stack will be closed when it goes out of scope. Here, in the context of a C function, to go out of
    /// scope means that the running function returns to Lua, or there is an error, or the slot is removed from the stack
    /// through `Lua.setTop()` or `Lua.pop()`, or there is a call to `Lua.closeSlot()`. A slot marked as to-be-closed should not be removed
    /// from the stack by any other function in the API except `Lua.setTop()` or `Lua.pop()`, unless previously deactivated by
    /// `Lua.closeSlot()`.
    ///
    /// This function should not be called for an index that is equal to or below an active to-be-closed slot.
    ///
    /// Note that, both in case of errors and of a regular return, by the time the `__close` metamethod runs, the C stack was
    /// already unwound, so that any automatic C variable declared in the calling function (e.g., a buffer) will be out of
    /// scope.
    ///
    /// Only available in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_toclose
    pub fn toClose(lua: *Lua, index: i32) void {
        c.lua_toclose(@ptrCast(lua), index);
    }

    /// Converts the Lua value at the given `index` to a signed integer
    /// The Lua value must be an integer, or a number, or a string convertible to an integer
    /// Returns an error if the conversion failed
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_tointeger'
    pub fn toInteger(lua: *Lua, index: i32) !Integer {
        switch (lang) {
            .lua51 => {
                const result = c.lua_tointeger(@ptrCast(lua), index);
                if (result == 0 and !lua.isNumber(index)) return error.LuaError;
                return result;
            },
            else => {
                var success: c_int = undefined;
                const result = c.lua_tointegerx(@ptrCast(lua), index, &success);
                if (success == 0) return error.LuaError;
                return result;
            },
        }
    }

    /// Converts the Lua value at the given `index` to a float
    /// The Lua value must be a number or a string convertible to a number
    /// Returns an error if the conversion failed
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_tonumber
    pub fn toNumber(lua: *Lua, index: i32) !Number {
        switch (lang) {
            .lua51 => {
                const result = c.lua_tonumber(@ptrCast(lua), index);
                if (result == 0 and !lua.isNumber(index)) return error.LuaError;
                return result;
            },
            else => {
                var success: c_int = undefined;
                const result = c.lua_tonumberx(@ptrCast(lua), index, &success);
                if (success == 0) return error.LuaError;
                return result;
            },
        }
    }

    /// Converts the value at the given index to a generic pointer (`*anyopaque`) The value can be a userdata, a table, a thread, a
    /// string, or a function; otherwise, `Lua.toPointer()` returns an error. Different objects will give different pointers. There is
    /// no way to convert the pointer back to its original value.
    ///
    /// Typically this function is used only for hashing and debug information.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_topointer
    pub fn toPointer(lua: *Lua, index: i32) !*const anyopaque {
        if (c.lua_topointer(@ptrCast(lua), index)) |ptr| return ptr;
        return error.LuaError;
    }

    /// Converts the Lua value at the given index to a slice. The
    /// Lua value must be a string or a number; otherwise, the function returns an error. If the value is a number, then
    /// `Lua.toString()` also changes the actual value in the stack to a string. (This change confuses `Lua.next()` when `Lua.toString()`
    /// is applied to keys during a table traversal.)
    ///
    /// `Lua.toString()` returns a pointer to a string inside the Lua state. This string always has a zero (`\0`)
    /// after its last character (as in C), but can contain other zeros in its body.
    ///
    /// Because Lua has garbage collection, there is no guarantee that the pointer returned by `Lua.toString()` will be valid
    /// after the corresponding Lua value is removed from the stack.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other` (Lua 5.2)
    /// * Errors: `memory` (All other versions)
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_tostring
    pub fn toString(lua: *Lua, index: i32) ![:0]const u8 {
        var length: usize = undefined;
        if (c.lua_tolstring(@ptrCast(lua), index, &length)) |ptr| return ptr[0..length :0];
        return error.LuaError;
    }

    /// Converts the value at the given `index` to a Lua thread.
    /// Returns an error if the value is not a thread
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_tothread
    pub fn toThread(lua: *Lua, index: i32) !*Lua {
        const thread = c.lua_tothread(@ptrCast(lua), index);
        if (thread) |thread_ptr| return @ptrCast(thread_ptr);
        return error.LuaError;
    }

    /// Converts the Lua value at the given index to an unsigned integer
    /// The Lua value must be a number or a string convertible to a number otherwise an error is returned
    ///
    /// Only available in Lua 5.2
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#lua_tounsignedx
    pub fn toUnsigned(lua: *Lua, index: i32) !Unsigned {
        var success: c_int = undefined;
        const result = c.lua_tounsignedx(@ptrCast(lua), index, &success);
        if (success == 0) return error.LuaError;
        return result;
    }

    /// Returns a Lua-owned userdata pointer of the given type at the given index.
    /// Works for both light and full userdata.
    /// Returns an error if the value is not a userdata.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_touserdata
    pub fn toUserdata(lua: *Lua, comptime T: type, index: i32) !*T {
        if (c.lua_touserdata(@ptrCast(lua), index)) |ptr| return @ptrCast(@alignCast(ptr));
        return error.LuaError;
    }

    /// Returns a Lua-owned userdata slice of the given type at the given index.
    /// Returns an error if the value is not a userdata.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_touserdata
    pub fn toUserdataSlice(lua: *Lua, comptime T: type, index: i32) ![]T {
        if (c.lua_touserdata(@ptrCast(lua), index)) |ptr| {
            const size = switch (lang) {
                .lua51, .luajit => lua.objectLen(index) / @sizeOf(T),
                .luau => @as(u32, @intCast(lua.objectLen(index))) / @sizeOf(T),
                else => lua.rawLen(index) / @sizeOf(T),
            };
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
        }
        return error.LuaError;
    }

    /// Only available in Luau
    pub fn toUserdataTagged(lua: *Lua, comptime T: type, index: i32, tag: i32) !*T {
        if (c.lua_touserdatatagged(@ptrCast(lua), index, tag)) |ptr| return @ptrCast(@alignCast(ptr));
        return error.LuaError;
    }

    /// Converts the Lua value at the given `index` to a 3- or 4-vector.
    /// The Lua value must be a vector.
    ///
    /// Only available in Luau
    pub fn toVector(lua: *Lua, index: i32) ![luau_vector_size]f32 {
        const res = c.lua_tovector(@ptrCast(lua), index);
        if (res) |r| {
            switch (luau_vector_size) {
                3 => return [_]f32{ r[0], r[1], r[2] },
                4 => return [_]f32{ r[0], r[1], r[2], r[3] },
                else => @compileError("invalid luau_vector_size - should not happen"),
            }
        }
        return error.LuaError;
    }

    /// Converts the Lua string at the given `index` to a string atom.
    /// The Lua value must be a string.
    ///
    /// Only available in Luau
    pub fn toStringAtom(lua: *Lua, index: i32) !struct { i32, [:0]const u8 } {
        var atom: c_int = undefined;
        if (c.lua_tostringatom(@ptrCast(lua), index, &atom)) |ptr| {
            return .{ atom, std.mem.span(ptr) };
        }
        return error.LuaError;
    }

    /// Retrieve the user atom index and name for the method being
    /// invoked in a namecall.
    ///
    /// Only available in Luau
    pub fn namecallAtom(lua: *Lua) !struct { i32, [:0]const u8 } {
        var atom: c_int = undefined;
        if (c.lua_namecallatom(@ptrCast(lua), &atom)) |ptr| {
            return .{ atom, std.mem.span(ptr) };
        }
        return error.LuaError;
    }

    /// Returns the `LuaType` of the value at the given index.
    /// `LuaType.none` is returned for a non-valid but acceptable index.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_type
    pub fn typeOf(lua: *Lua, index: i32) LuaType {
        return @enumFromInt(c.lua_type(@ptrCast(lua), index));
    }

    /// Returns the name of the given `LuaType` as a null-terminated slice
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_typename
    pub fn typeName(lua: *Lua, t: LuaType) [:0]const u8 {
        return std.mem.span(c.lua_typename(@ptrCast(lua), @intFromEnum(t)));
    }

    /// Returns the pseudo-index that represents the `i`th upvalue of the running function
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_upvalueindex
    pub fn upvalueIndex(i: i32) i32 {
        return c.lua_upvalueindex(i);
    }

    /// Returns the version number of this core
    /// When `caller_version` is true it returns the address of the version running the call
    /// See https://www.lua.org/manual/5.3/manual.html#lua_version
    fn version52(lua: *Lua, caller_version: bool) *const Number {
        if (caller_version) return c.lua_version(null);
        return c.lua_version(@ptrCast(lua));
    }

    /// Returns the version number of this core
    /// See https://www.lua.org/manual/5.4/manual.html#lua_version
    fn version54(lua: *Lua) Number {
        return c.lua_version(@ptrCast(lua));
    }

    /// Lua 5.2 and 5.3: Returns the address of the version number stored in the Lua core. When `caller_version` is false, returns the
    /// address of the version used to create that state. When `caller_version` is true, returns the address of the version running the call.
    ///
    /// Lua 5.4: Returns the version number of this core.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_version
    pub const version = switch (lang) {
        .lua54 => version54,
        else => version52,
    };

    /// Emits a warning with the given `message`
    /// A message with `to_cont` as true should be continued in a subsequent call to the function.
    ///
    /// Only available in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_warning
    pub fn warning(lua: *Lua, message: [:0]const u8, to_cont: bool) void {
        c.lua_warning(@ptrCast(lua), message.ptr, @intFromBool(to_cont));
    }

    /// Exchange values between different threads of the same state.
    /// This function pops `n` values from the current stack, and pushes them onto the stack of `to`.
    ///
    /// * Pops:   `?`
    /// * Pushes: `?`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_xmove
    pub fn xMove(lua: *Lua, to: *Lua, num: i32) void {
        c.lua_xmove(@ptrCast(lua), @ptrCast(to), num);
    }

    /// This function is equivalent to `Lua.yieldCont()` but has no continuation
    /// This function never returns
    /// See https://www.lua.org/manual/5.4/manual.html#lua_yield
    pub fn yield(lua: *Lua, num_results: i32) switch (lang) {
        .lua51, .luajit, .luau => i32,
        else => noreturn,
    } {
        switch (lang) {
            .lua51, .luajit, .luau => return c.lua_yield(@ptrCast(lua), num_results),
            else => {
                _ = c.lua_yieldk(@ptrCast(lua), num_results, 0, null);
                unreachable;
            },
        }
    }

    fn yieldCont52(lua: *Lua, num_results: i32, ctx: i32, k: CFn) noreturn {
        _ = c.lua_yieldk(@ptrCast(lua), num_results, ctx, k);
        unreachable;
    }

    fn yieldCont53(lua: *Lua, num_results: i32, ctx: Context, k: CContFn) noreturn {
        _ = c.lua_yieldk(@ptrCast(lua), num_results, ctx, k);
        unreachable;
    }

    /// Yields this coroutine (thread)
    /// This function never returns
    /// See https://www.lua.org/manual/5.4/manual.html#lua_yieldk
    pub const yieldCont = switch (lang) {
        .lua53, .lua54 => yieldCont53,
        else => yieldCont52,
    };

    // Debug library functions
    //
    // The debug interface functions are included in alphabetical order
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Returns the current hook function
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gethook
    pub fn getHook(lua: *Lua) ?CHookFn {
        return c.lua_gethook(@ptrCast(lua));
    }

    /// Returns the current hook count
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gethookcount
    pub fn getHookCount(lua: *Lua) i32 {
        return c.lua_gethookcount(@ptrCast(lua));
    }

    /// Returns the current hook mask
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_gethookmask
    pub fn getHookMask(lua: *Lua) HookMask {
        return HookMask.fromInt(c.lua_gethookmask(@ptrCast(lua)));
    }

    fn getInfoLua(lua: *Lua, options: DebugInfo.Options, info: *DebugInfo) void {
        const str = options.toString();

        var ar: Debug = undefined;

        switch (lang) {
            .lua51, .luajit => ar.i_ci = info.private,
            else => ar.i_ci = @ptrCast(info.private),
        }

        // should never fail because we are controlling options with the struct param
        _ = c.lua_getinfo(@ptrCast(lua), &str, &ar);
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
        if (lang == .lua54 and options.r) {
            info.first_transfer = ar.ftransfer;
            info.num_transfer = ar.ntransfer;
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
        if (lang == .lua51 or lang == .luajit) return;

        if (options.t) info.is_tail_call = ar.istailcall != 0;
        if (options.u) {
            info.num_upvalues = ar.nups;
            info.num_params = ar.nparams;
            info.is_vararg = ar.isvararg != 0;
        }
    }

    fn getInfoLuau(lua: *Lua, level: i32, options: DebugInfo.Options, info: *DebugInfo) void {
        const str = options.toString();

        var ar: Debug = undefined;

        // should never fail because we are controlling options with the struct param
        _ = c.lua_getinfo(@ptrCast(lua), level, &str, &ar);
        // std.debug.assert( != 0);

        // copy data into a struct
        if (options.l) info.current_line = if (ar.currentline == -1) null else ar.currentline;
        if (options.n) {
            info.name = if (ar.name != null) std.mem.span(ar.name) else null;
        }
        if (options.s) {
            info.source = std.mem.span(ar.source);
            // TODO: short_src figureit out
            @memcpy(&info.short_src, ar.short_src[0..c.LUA_IDSIZE]);
            info.first_line_defined = ar.linedefined;
            info.what = blk: {
                const what = std.mem.span(ar.what);
                if (std.mem.eql(u8, "Lua", what)) break :blk .lua;
                if (std.mem.eql(u8, "C", what)) break :blk .c;
                if (std.mem.eql(u8, "main", what)) break :blk .main;
                if (std.mem.eql(u8, "tail", what)) break :blk .tail;
                unreachable;
            };
        }
    }

    /// Gets information about a specific function or function invocation
    ///
    /// * Pops:   `(0|1)`
    /// * Pushes: `(0|1|2)`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getinfo
    pub const getInfo = if (lang == .luau) getInfoLuau else getInfoLua;

    fn getLocalLua(lua: *Lua, info: *DebugInfo, n: i32) ![:0]const u8 {
        var ar: Debug = undefined;

        switch (lang) {
            .lua51, .luajit => ar.i_ci = info.private,
            else => ar.i_ci = @ptrCast(info.private),
        }

        if (c.lua_getlocal(@ptrCast(lua), &ar, n)) |name| {
            return std.mem.span(name);
        }
        return error.LuaError;
    }

    fn getLocalLuau(lua: *Lua, level: i32, n: i32) ![:0]const u8 {
        if (c.lua_getlocal(@ptrCast(lua), level, n)) |name| {
            return std.mem.span(name);
        }
        return error.LuaError;
    }

    /// Gets information about a local variable or a temporary value of a given activation record or a given function.
    ///
    /// In the first case, the parameter ar must be a valid activation record that was filled by a previous call to
    /// `Lua.getStack()` or given as argument to a hook. The index n selects which local variable to inspect; see
    /// debug.getlocal for details about variable indices and names.
    ///
    /// `Lua.getLocal()` pushes the variable's value onto the stack and returns its name.
    ///
    /// In the second case, ar must be NULL and the function to be inspected must be on the top of the stack. In this case,
    /// only parameters of Lua functions are visible (as there is no information about what variables are active) and no values
    /// are pushed onto the stack.
    ///
    /// Returns an error (and pushes nothing) when the index is greater than the number of active local variables.
    ///
    /// * Pops:   `0`
    /// * Pushes: `(0|1)`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getlocal
    pub const getLocal = if (lang == .luau) getLocalLuau else getLocalLua;

    /// Gets information about the interpreter runtime stack.
    ///
    /// This function returns a `DebugInfo` structure with an identification of the activation record of the function
    /// executing at a given level. Level `0` is the current running function, whereas level `n+1` is the function that has called
    /// level `n` (except for tail calls, which do not count in the stack). When called with a level greater than the stack
    /// depth, `Lua.getStack()` returns an error.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getstack
    pub fn getStack(lua: *Lua, level: i32) !DebugInfo {
        var ar: Debug = undefined;
        if (c.lua_getstack(@ptrCast(lua), level, &ar) == 0) return error.LuaError;
        return DebugInfo{
            .private = switch (lang) {
                .lua51, .luajit => ar.i_ci,
                else => ar.i_ci.?,
            },
        };
    }

    /// Gets information about the `n`-th upvalue of the closure at index `func_index`. It pushes the upvalue's value onto the stack
    /// and returns its name. Returns an error (and pushes nothing) when the index `n` is greater than the number of upvalues.
    /// See debug.getupvalue for more information about upvalues.
    ///
    /// * Pops:   `0`
    /// * Pushes: `(0|1)`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_getupvalue
    pub fn getUpvalue(lua: *Lua, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_getupvalue(@ptrCast(lua), func_index, n)) |name| {
            return std.mem.span(name);
        }
        return error.LuaError;
    }

    /// Sets the debugging hook function.
    ///
    /// * Argument `f` is the hook function
    /// * `mask` specifies on which events the hook will be called.
    /// * The count argument is only meaningful when the mask includes `count`
    ///
    /// For each event, the hook is called as explained below:
    /// * The call hook: is called when the interpreter calls a function. The hook is called just after Lua enters the new
    /// function.
    /// * The return hook: is called when the interpreter returns from a function. The hook is called just before Lua
    /// leaves the function.
    /// * The line hook: is called when the interpreter is about to start the execution of a new line of
    /// code, or when it jumps back in the code (even to the same line). This event only happens while Lua is executing a Lua
    /// function.
    /// * The count hook: is called after the interpreter executes every count instructions. This event only happens
    /// while Lua is executing a Lua function.
    ///
    /// Hooks are disabled by setting mask to zero.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_sethook
    /// TODO: allow setting mask to null to set to zero?
    pub fn setHook(lua: *Lua, f: CHookFn, mask: HookMask, count: i32) void {
        const hook_mask = HookMask.toInt(mask);
        // Lua 5.1 and 5.2 always return 1. Other versions return void
        _ = c.lua_sethook(@ptrCast(lua), f, hook_mask, count);
    }

    fn setLocalLua(lua: *Lua, info: *DebugInfo, n: i32) ![:0]const u8 {
        var ar: Debug = undefined;

        switch (lang) {
            .lua51, .luajit => ar.i_ci = info.private,
            else => ar.i_ci = @ptrCast(info.private),
        }

        if (c.lua_setlocal(@ptrCast(lua), &ar, n)) |name| {
            return std.mem.span(name);
        }
        return error.LuaError;
    }

    fn setLocalLuau(lua: *Lua, level: i32, n: i32) ![:0]const u8 {
        if (c.lua_setlocal(@ptrCast(lua), level, n)) |name| {
            return std.mem.span(name);
        }
        return error.LuaError;
    }

    /// Sets the value of a local variable of a given activation record. It assigns the value on the top of the stack to the
    /// variable and returns its name. It also pops the value from the stack.
    ///
    /// Returns an error (and pops nothing) when the index is greater than the number of active local variables.
    /// Parameters `ar` and `n` are as in the function `Lua.getLocal()`.
    ///
    /// * Pops:   `(0|1)`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setlocal
    pub const setLocal = if (lang == .luau) setLocalLuau else setLocalLua;

    /// Sets the value of a closure's upvalue. It assigns the value on the top of the stack to the upvalue and returns its
    /// name. It also pops the value from the stack.
    /// Returns an error (and pops nothing) when the index `n` is greater than the number of upvalues.
    ///
    /// Parameters `func_index` and `n` are as in the function lua_getupvalue.
    ///
    /// * Pops:   `(0|1)`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_setupvalue
    pub fn setUpvalue(lua: *Lua, func_index: i32, n: i32) ![:0]const u8 {
        if (c.lua_setupvalue(@ptrCast(lua), func_index, n)) |name| {
            return std.mem.span(name);
        }
        return error.LuaError;
    }

    /// Only available in Luau
    pub fn setInterruptCallbackFn(lua: *Lua, cb: ?CInterruptCallbackFn) void {
        if (c.lua_callbacks(@ptrCast(lua))) |cb_struct| {
            cb_struct.*.interrupt = cb;
        }
    }

    /// Only available in Luau
    pub fn setUserAtomCallbackFn(lua: *Lua, cb: CUserAtomCallbackFn) void {
        if (c.lua_callbacks(@ptrCast(lua))) |cb_struct| {
            cb_struct.*.useratom = cb;
        }
    }

    /// Returns a unique identifier for the upvalue numbered `n` from the closure at index funcindex.
    ///
    /// These unique identifiers allow a program to check whether different closures share upvalues. Lua closures that share an
    /// upvalue (that is, that access a same external local variable) will return identical ids for those upvalue indices.
    ///
    /// Parameters `func_index` and `n` are as in the function `Lua.getUpvalue()`, but `n` cannot be greater than the number of upvalues.
    ///
    /// Not implemented in Lua 5.1, LuaJIT or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_upvalueid
    pub fn upvalueId(lua: *Lua, func_index: i32, n: i32) !*anyopaque {
        if (c.lua_upvalueid(@ptrCast(lua), func_index, n)) |ptr| return ptr;
        return error.LuaError;
    }

    /// Make the `n1`-th upvalue of the Lua closure at index `func_index1` refer to the `n2`-th upvalue of the Lua closure at index
    /// `func_index2`.
    ///
    /// Not implemented in Lua 5.1, LuaJIT or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_upvaluejoin
    pub fn upvalueJoin(lua: *Lua, func_index1: i32, n1: i32, func_index2: i32, n2: i32) void {
        c.lua_upvaluejoin(@ptrCast(lua), func_index1, n1, func_index2, n2);
    }

    // Auxiliary library functions
    //
    // Auxiliary library functions are included in alphabetical order.
    // Each is kept similar to the original C API function while also making it easy to use from Zig

    /// Checks whether `cond` is true. Raises an error using `Lua.argError()` if not
    /// Possibly never returns.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_argcheck
    pub fn argCheck(lua: *Lua, cond: bool, arg: i32, extra_msg: [:0]const u8) void {
        // translate-c failed
        if (!cond) lua.argError(arg, extra_msg);
    }

    /// Raises an error reporting a problem with argument `arg` of the C function that called it
    /// using a standard message that includes extramsg as a comment: bad argument #arg to 'funcname' (extramsg)
    ///
    ///  This function never returns.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_argerror
    pub fn argError(lua: *Lua, arg: i32, extra_msg: [:0]const u8) noreturn {
        _ = c.luaL_argerror(@as(*LuaState, @ptrCast(lua)), arg, extra_msg.ptr);
        unreachable;
    }

    /// Checks whether `cond` is true. Raises an error using `Lua.typeError()` if not
    /// Possibly never returns
    ///
    /// Only available in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_argexpected
    pub fn argExpected(lua: *Lua, cond: bool, arg: i32, type_name: [:0]const u8) void {
        // translate-c failed
        if (!cond) lua.typeError(arg, type_name);
    }

    /// Calls a metamethod.
    ///
    /// If the object at index `obj` has a metatable and this metatable has a field `field`,
    /// this function calls this field passing the object as its only argument.
    /// In this case this function pushes onto the stack the value returned by the call.
    /// If there is no metatable or no metamethod, this function returns an error without pushing any value on the stack.
    ///
    /// * Pops:   `0`
    /// * Pushes: `(0|1)`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_callmeta
    pub fn callMeta(lua: *Lua, obj: i32, field: [:0]const u8) !void {
        if (c.luaL_callmeta(@ptrCast(lua), obj, field.ptr) == 0) return error.LuaError;
    }

    /// Checks whether the function has an argument of any type (including nil) at position `arg`
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkany
    pub fn checkAny(lua: *Lua, arg: i32) void {
        c.luaL_checkany(@ptrCast(lua), arg);
    }

    /// Checks whether the function argument `arg` is a number and returns this number cast to an i32
    ///
    /// Not available in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#luaL_checkint
    /// TODO: is this ever useful?
    pub fn checkInt(lua: *Lua, arg: i32) i32 {
        return c.luaL_checkint(@ptrCast(lua), arg);
    }

    /// Checks whether the function argument `arg` is an integer (or can be converted to an integer) and returns the integer
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkinteger
    pub fn checkInteger(lua: *Lua, arg: i32) Integer {
        return c.luaL_checkinteger(@ptrCast(lua), arg);
    }

    /// Checks whether the function argument `arg` is a number and returns the number
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checknumber
    pub fn checkNumber(lua: *Lua, arg: i32) Number {
        return c.luaL_checknumber(@ptrCast(lua), arg);
    }

    /// Returns the enum value found, or raises a Lua error otherwise
    ///
    /// Useful for mapping Lua strings to Zig enums
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkoption
    pub fn checkOption(lua: *Lua, comptime T: type, arg: i32, default: ?T) T {
        const name = blk: {
            if (default) |defaultName| {
                break :blk lua.optString(arg) orelse @tagName(defaultName);
            } else {
                break :blk lua.checkString(arg);
            }
        };

        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return @enumFromInt(field.value);
            }
        }

        return lua.argError(arg, lua.pushFString("invalid option '%s'", .{name.ptr}));
    }

    /// Grows the stack size to top + `size` elements, raising an error if the stack cannot grow to that size.
    /// `msg` is an additional text to go into the error message
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkstack
    pub fn checkStackErr(lua: *Lua, size: i32, msg: ?[:0]const u8) void {
        c.luaL_checkstack(@ptrCast(lua), size, if (msg) |m| m.ptr else null);
    }

    /// Checks whether the function argument `arg` is a string and returns the string.
    /// This uses the same underlying Lua function (lua_tolstring) that `Lua.toString()` uses,
    /// so all conversions and caveats of that function apply here.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkstring
    pub fn checkString(lua: *Lua, arg: i32) [:0]const u8 {
        var length: usize = 0;
        const str = c.luaL_checklstring(@ptrCast(lua), arg, &length);
        // luaL_checklstring never returns null (throws lua error)
        return str[0..length :0];
    }

    /// Checks whether the function argument `arg` has type `t`
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checktype
    pub fn checkType(lua: *Lua, arg: i32, t: LuaType) void {
        c.luaL_checktype(@ptrCast(lua), arg, @intFromEnum(t));
    }

    /// Checks whether the function argument `arg` is a userdata of the type `name`.
    /// Returns a pointer to the userdata
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkudata
    pub fn checkUserdata(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) *T {
        // the returned pointer will not be null
        return @ptrCast(@alignCast(c.luaL_checkudata(@ptrCast(lua), arg, name.ptr).?));
    }

    /// Checks whether the function argument `arg` is a userdata of the type `name`.
    /// Returns a Lua-owned userdata slice
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkudata
    pub fn checkUserdataSlice(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) []T {
        // the returned pointer will not be null
        const ptr = c.luaL_checkudata(@ptrCast(lua), arg, name.ptr).?;
        const size = switch (lang) {
            .lua51, .luajit => lua.objectLen(arg) / @sizeOf(T),
            .luau => @as(u32, @intCast(lua.objectLen(arg))) / @sizeOf(T),
            else => lua.rawLen(arg) / @sizeOf(T),
        };
        return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
    }

    /// Checks whether the function argument arg is a number and returns this number cast to an unsigned
    ///
    /// Only available in Lua 5.2
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#luaL_checkunsigned
    pub fn checkUnsigned(lua: *Lua, arg: i32) Unsigned {
        return c.luaL_checkunsigned(@ptrCast(lua), arg);
    }

    /// Checks whether the function argument `arg` is a vector and returns the vector as a floating point slice.
    ///
    /// Only available in Luau
    pub fn checkVector(lua: *Lua, arg: i32) [luau_vector_size]f32 {
        const vec = lua.toVector(arg) catch {
            lua.typeError(arg, lua.typeName(LuaType.vector));
        };
        return vec;
    }

    fn checkVersion52(lua: *Lua) void {
        return c.luaL_checkversion_(@ptrCast(lua), c.LUA_VERSION_NUM);
    }

    fn checkVersion53(lua: *Lua) void {
        return c.luaL_checkversion_(@ptrCast(lua), c.LUA_VERSION_NUM, c.LUAL_NUMSIZES);
    }

    /// Checks whether the code making the call and the Lua library being called are using
    /// the same version of Lua and the same numeric types.
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkversion
    pub const checkVersion = switch (lang) {
        .lua53, .lua54 => checkVersion53,
        else => checkVersion52,
    };

    /// Loads and runs the given file, potentially returning an error.
    ///
    /// * Pops:   `0`
    /// * Pushes: `?`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_dofile
    pub fn doFile(lua: *Lua, file_name: [:0]const u8) !void {
        // translate-c failure
        switch (lang) {
            .luajit, .lua51 => try lua.loadFile(file_name),
            else => try lua.loadFile(file_name, .binary_text),
        }
        try lua.protectedCall(.{ .results = mult_return });
    }

    /// Loads and runs the given string, potentially returning an error.
    ///
    /// * Pops:   `0`
    /// * Pushes: `?`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_dostring
    pub fn doString(lua: *Lua, str: [:0]const u8) !void {
        // trnaslate-c failure
        try lua.loadString(str);
        try lua.protectedCall(.{ .results = mult_return });
    }

    /// Raises an error
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_error
    pub fn raiseErrorStr(lua: *Lua, fmt: [:0]const u8, args: anytype) noreturn {
        _ = @call(
            .auto,
            if (lang == .luau) c.luaL_errorL else c.luaL_error,
            .{ @as(*LuaState, @ptrCast(lua)), fmt.ptr } ++ args,
        );
        unreachable;
    }

    /// Raises an error from inside a Luau interrupt
    /// See https://github.com/luau-lang/luau/blob/ce8495a69e7a4e774a5402f99e1fc282a92ced91/CLI/Repl.cpp#L59
    ///
    /// Only available in Luau
    pub fn raiseInterruptErrorStr(lua: *Lua, fmt: [:0]const u8, args: anytype) noreturn {
        if (lang != .luau) return;
        c.lua_rawcheckstack(@ptrCast(lua), 1);
        lua.raiseErrorStr(fmt, args);
        unreachable;
    }

    /// This function produces the return values for process-related functions in the standard library (os.execute and io.close).
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `3`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_execresult
    pub fn execResult(lua: *Lua, stat: i32) i32 {
        return c.luaL_execresult(@ptrCast(lua), stat);
    }

    /// This function produces the return values for file-related functions in the standard library
    /// (io.open, os.rename, file:seek, etc.).
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `(1|3)`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_fileresult
    pub fn fileResult(lua: *Lua, stat: i32, file_name: [:0]const u8) i32 {
        return c.luaL_fileresult(@ptrCast(lua), stat, file_name.ptr);
    }

    /// Pushes onto the stack the field `e` from the metatable of the object at index `obj`
    /// and returns the type of the pushed value. If the object does not have a
    /// metatable, or if the metatable does not have this field, pushes nothing and the tupe returned is nil.
    ///
    /// * Pops:   `0`
    /// * Pushes: `(0|1)`
    /// * Errors: `memory`
    ///
    /// TODO: possibly return an error if nil
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_getmetafield
    pub fn getMetaField(lua: *Lua, obj: i32, field: [:0]const u8) !LuaType {
        const val_type: LuaType = @enumFromInt(c.luaL_getmetafield(@ptrCast(lua), obj, field.ptr));
        if (val_type == .nil) return error.LuaError;
        return val_type;
    }

    /// Pushes onto the stack the metatable associated with the name tname in the
    /// registry (see `Lua.newMetatable()`), or nil if there is no metatable associated
    /// with that name. Returns the type of the pushed value.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// TODO: return error when type is nil?
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_getmetatable
    pub fn getMetatableRegistry(lua: *Lua, table_name: [:0]const u8) LuaType {
        switch (lang) {
            .lua53, .lua54, .luau => return @enumFromInt(c.luaL_getmetatable(@as(*LuaState, @ptrCast(lua)), table_name.ptr)),
            else => {
                c.luaL_getmetatable(@as(*LuaState, @ptrCast(lua)), table_name.ptr);
                return lua.typeOf(-1);
            },
        }
    }

    /// Ensures that the value `t[field]`, where `t` is the value at `index`, is a table, and pushes that table onto the stack.
    /// Returns true if it finds a previous table there and false if it creates a new table.
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_getsubtable
    pub fn getSubtable(lua: *Lua, index: i32, field: [:0]const u8) bool {
        return c.luaL_getsubtable(@ptrCast(lua), index, field.ptr) != 0;
    }

    /// Creates a copy of string `str`, replacing any occurrence of the string `pat` with the string `rep`
    /// Pushes the resulting string on the stack and returns it.
    ///
    /// Not available in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_gsub
    pub fn globalSub(lua: *Lua, str: [:0]const u8, pat: [:0]const u8, rep: [:0]const u8) []const u8 {
        const s = c.luaL_gsub(@ptrCast(lua), str.ptr, pat.ptr, rep.ptr);
        const l = lua.rawLen(-1);
        return s[0..l];
    }

    /// Returns the "length" of the value at the given index as a number
    /// it is equivalent to the '#' operator in Lua. Raises a Lua error if the
    /// result of the operation is not an integer. (This case can only happen through metamethods.)
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_len
    pub fn lenRaiseErr(lua: *Lua, index: i32) i64 {
        return c.luaL_len(@ptrCast(lua), index);
    }

    fn loadBuffer51(lua: *Lua, buf: []const u8, name: [:0]const u8) !void {
        switch (c.luaL_loadbuffer(@ptrCast(lua), buf.ptr, buf.len, name.ptr)) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.LuaSyntax,
            StatusCode.err_memory => return error.OutOfMemory,
            else => unreachable,
        }
    }

    fn loadBuffer52(lua: *Lua, buf: []const u8, name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        switch (c.luaL_loadbufferx(@ptrCast(lua), buf.ptr, buf.len, name.ptr, mode_str.ptr)) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.LuaSyntax,
            StatusCode.err_memory => return error.OutOfMemory,
            else => unreachable,
        }
    }

    /// Loads a buffer as a Lua chunk
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_loadbufferx
    pub const loadBuffer = switch (lang) {
        .lua51, .luajit => loadBuffer51,
        else => loadBuffer52,
    };

    /// Loads bytecode binary (as compiled with f.ex. 'luau-compile --binary')
    /// See https://luau-lang.org/getting-started
    /// See also condsiderations for binary bytecode compatibility/safety: https://github.com/luau-lang/luau/issues/493#issuecomment-1185054665
    pub fn loadBytecode(lua: *Lua, chunkname: [:0]const u8, bytecode: []const u8) !void {
        if (c.luau_load(@ptrCast(lua), chunkname.ptr, bytecode.ptr, bytecode.len, 0) != 0) return error.LuaError;
    }

    fn loadFile51(lua: *Lua, file_name: [:0]const u8) !void {
        const ret = c.luaL_loadfile(@ptrCast(lua), file_name.ptr);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.LuaSyntax,
            StatusCode.err_memory => return error.OutOfMemory,
            err_file => return error.LuaFile,
            else => unreachable,
        }
    }

    fn loadFile52(lua: *Lua, file_name: [:0]const u8, mode: Mode) !void {
        const mode_str = switch (mode) {
            .binary => "b",
            .text => "t",
            .binary_text => "bt",
        };
        const ret = c.luaL_loadfilex(@ptrCast(lua), file_name.ptr, mode_str.ptr);
        switch (ret) {
            StatusCode.ok => return,
            StatusCode.err_syntax => return error.LuaSyntax,
            StatusCode.err_memory => return error.OutOfMemory,
            err_file => return error.LuaFile,
            // NOTE: the docs mention possible other return types, but I couldn't figure them out
            else => unreachable,
        }
    }

    /// Loads a file as a Lua chunk
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_loadfilex
    pub const loadFile = switch (lang) {
        .lua51, .luajit => loadFile51,
        else => loadFile52,
    };

    /// Loads a string as a Lua chunk
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_loadstring
    pub fn loadString(lua: *Lua, str: [:0]const u8) !void {
        switch (lang) {
            .luau => {
                var size: usize = 0;
                const bytecode = c.luau_compile(str.ptr, str.len, null, &size);

                // Failed to allocate memory for the out buffer
                if (bytecode == null) return error.OutOfMemory;

                // luau_compile uses malloc to allocate the bytecode on the heap
                defer zig_luau_free(bytecode);
                try lua.loadBytecode("...", bytecode[0..size]);
            },
            else => {
                const ret = c.luaL_loadstring(@ptrCast(lua), str.ptr);
                switch (ret) {
                    StatusCode.ok => return,
                    StatusCode.err_syntax => return error.LuaSyntax,
                    StatusCode.err_memory => return error.OutOfMemory,
                    // loadstring runs lua_load which runs pcall, so can also return any result of an pcall error
                    StatusCode.err_runtime => return error.LuaRuntime,
                    StatusCode.err_error => return error.LuaMsgHandler,
                    else => unreachable,
                }
            },
        }
    }

    /// Creates a new table and registers there the functions in `list`
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_newlib
    pub fn newLib(lua: *Lua, list: []const FnReg) void {
        // translate-c failure
        lua.checkVersion();
        lua.newLibTable(list);
        lua.setFuncs(list, 0);
    }

    /// Creates a new table with a size optimized to store all entries in the array `list`
    /// (but does not actually store them). It is intended to be used in conjunction with `Lua.setFuncs()`
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_newlibtable
    pub fn newLibTable(lua: *Lua, list: []const FnReg) void {
        // translate-c failure
        lua.createTable(0, @intCast(list.len));
    }

    /// If the registry already has the key `key`, returns an error
    /// Otherwise, creates a new table to be used as a metatable for userdata,
    /// adds to this new table the pair `__name = tname`,
    /// and adds to the registry the pair `[tname] = new table`.
    ///
    /// In both cases, the function pushes onto the stack the final value associated with tname in the registry.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_newmetatable
    pub fn newMetatable(lua: *Lua, key: [:0]const u8) !void {
        if (c.luaL_newmetatable(@ptrCast(lua), key.ptr) == 0) return error.LuaError;
    }

    // luaL_opt (a macro) really isn't that useful, so not going to implement for now

    /// If the function argument `arg` is a number, returns this number cast to an i32.
    /// If the argument is absent or nil returns null. Otherwise raises an error
    ///
    /// Not available in Lua 5.3 and 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#luaL_optint
    /// TODO: just like checkInt, is this ever useful?
    pub fn optInt(lua: *Lua, arg: i32) ?i32 {
        if (lua.isNoneOrNil(arg)) return null;
        return lua.checkInt(arg);
    }

    /// If the function argument `arg` is an integer, (or it is convertible to an
    /// integer) returns the integer. If the argument is absent or nil returns null.
    /// Otherwise raises an error
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_optinteger
    pub fn optInteger(lua: *Lua, arg: i32) ?Integer {
        if (lua.isNoneOrNil(arg)) return null;
        return lua.checkInteger(arg);
    }

    /// If the function argument `arg` is a number, returns the number
    /// If the argument is absent or nil returns null. Otherwise, raises an error.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_optnumber
    pub fn optNumber(lua: *Lua, arg: i32) ?Number {
        if (lua.isNoneOrNil(arg)) return null;
        return lua.checkNumber(arg);
    }

    /// If the function argument `arg` is a string, returns the string
    /// If the argment is absent or nil returns null. Otherwise raises an error.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_optstring
    pub fn optString(lua: *Lua, arg: i32) ?[:0]const u8 {
        if (lua.isNoneOrNil(arg)) return null;
        return lua.checkString(arg);
    }

    /// If the function argument is a number, returns this number as an unsigned
    /// If the argument is absent or nil returns null, otherwise raises an error
    ///
    /// Only available in Lua 5.2
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.2/manual.html#luaL_optunsigned
    pub fn optUnsigned(lua: *Lua, arg: i32) ?Unsigned {
        if (lua.isNoneOrNil(arg)) return null;
        return lua.checkUnsigned(arg);
    }

    /// Pushes the fail value onto the stack
    ///
    /// Only available in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_pushfail
    pub fn pushFail(lua: *Lua) void {
        c.luaL_pushfail(@as(*LuaState, @ptrCast(lua)));
    }

    /// Creates and returns a reference in the table at index `index` for the object on the top of the stack
    /// Pops the object
    ///
    /// A reference is a unique integer key. As long as you do not manually add integer
    /// keys into the table t, `Lua.ref()` ensures the uniqueness of the key it returns.
    /// You can retrieve an object referred by the reference r by calling
    /// `Lua.rawGetIndex(index, r)`. The function `Lua.unref()` frees a reference.
    ///
    /// If the object on the top of the stack is nil, `Lua.ref()` returns the constant
    /// `ref_nil`. The constant `ref_no` is guaranteed to be different from any
    /// reference returned by `Lua.ref()`.
    ///
    /// * Pops:   `1`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_ref
    pub fn ref(lua: *Lua, index: i32) !i32 {
        const ret = if (lang == .luau) c.lua_ref(@ptrCast(lua), index) else c.luaL_ref(@ptrCast(lua), index);
        return if (ret == ref_nil) error.LuaError else ret;
    }

    /// Opens a library
    ///
    /// When called with libname equal to `null`, it simply registers all functions in
    /// the list `funcs` (see luaL_Reg) into the table on the top of the stack.
    ///
    /// When called with a non-null libname, `Lua.registerFns` creates a new table t, sets
    /// it as the value of the global variable `libname`, sets it as the value of
    /// `package.loaded[libname]`, and registers on it all functions in the list `funcs`. If
    /// there is a table in `package.loaded[libname]` or in variable `libname`, reuses this
    /// table instead of creating a new one.
    ///
    /// In any case the function leaves the table on the top of the stack.
    ///
    /// Only available in Lua 5.1, LuaJIT, and Luau
    ///
    /// * Pops:   `(0|1)`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    ///
    /// See https://www.lua.org/manual/5.1/manual.html#luaL_register
    pub fn registerFns(lua: *Lua, libname: ?[:0]const u8, funcs: []const FnReg) void {
        // translated from the implementation of luaI_openlib so we can use a slice of
        // FnReg without requiring a sentinel end value
        if (libname) |name| {
            _ = c.luaL_findtable(@ptrCast(lua), registry_index, "_LOADED", 1);
            _ = lua.getField(-1, name);
            if (!lua.isTable(-1)) {
                lua.pop(1);
                if (c.luaL_findtable(@ptrCast(lua), globals_index, name, @intCast(funcs.len))) |_| {
                    switch (lang) {
                        .luau => lua.raiseErrorStr("name conflict for module '%s'", .{name.ptr}),
                        else => lua.raiseErrorStr("name conflict for module " ++ c.LUA_QS, .{name.ptr}),
                    }
                }
                lua.pushValue(-1);
                lua.setField(-3, name);
            }
            lua.remove(-2);
            lua.insert(-1);
        }
        for (funcs) |f| {
            // TODO: handle null functions
            lua.pushFunction(f.func.?);
            lua.setField(-2, f.name);
        }
    }

    /// If package.loaded[`mod_name`] is not true, calls the function `open_fn` with `mod_name`
    /// as an argument and sets the call result to package.loaded[`mod_name`] as if that function
    /// has been called through require.
    ///
    /// If `global` is true, also stores the module into the global `mod_name`.
    ///
    /// Leaves a copy of the module on the stack.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_requiref
    pub fn requireF(lua: *Lua, mod_name: [:0]const u8, open_fn: CFn, global: bool) void {
        switch (lang) {
            .lua51, .luajit, .luau => {
                lua.pushFunction(open_fn);
                _ = lua.pushStringZ(mod_name);
                lua.call(.{ .args = 1 });
            },
            else => c.luaL_requiref(@ptrCast(lua), mod_name.ptr, open_fn, @intFromBool(global)),
        }
    }

    /// Registers all functions in the array `fns` into the table on the top of the stack
    ///
    /// All functions are created with `num_upvalues` upvalues initialized
    /// with copies of the `num_upvalues` values previously pushed on the stack on top of the
    /// library table. These values are popped from the stack after the registration.
    ///
    /// A function with a `null` value represents a placeholder, which is filled with
    /// false.
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `num_upvalues`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_setfuncs
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
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_setmetatable
    pub fn setMetatableRegistry(lua: *Lua, table_name: [:0]const u8) void {
        c.luaL_setmetatable(@ptrCast(lua), table_name.ptr);
    }

    /// This function works like `Lua.checkUserdata()` except it returns a Zig error instead of raising a Lua error on fail
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_testudata
    pub fn testUserdata(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) !*T {
        if (c.luaL_testudata(@ptrCast(lua), arg, name.ptr)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        } else return error.LuaError;
    }

    /// This function works like `Lua.checkUserdataSlice()` except it returns a Zig error instead of raising a Lua error on fail
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_checkudata
    pub fn testUserdataSlice(lua: *Lua, comptime T: type, arg: i32, name: [:0]const u8) ![]T {
        if (c.luaL_testudata(@ptrCast(lua), arg, name.ptr)) |ptr| {
            const size = lua.rawLen(arg) / @sizeOf(T);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..size];
        } else return error.LuaError;
    }

    /// Converts any Lua value at the given index into a string in a reasonable format
    /// Uses the __tostring metamethod if available
    ///
    /// Not available in Lua 5.1, LuaJIT, or Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_tolstring
    pub fn toStringEx(lua: *Lua, index: i32) [:0]const u8 {
        var length: usize = undefined;
        const ptr = c.luaL_tolstring(@ptrCast(lua), index, &length);
        return ptr[0..length :0];
    }

    /// Creates and pushes a traceback of the stack of `state`. If `msg` is not `null`, it is
    /// appended at the beginning of the traceback. The `level` parameter tells at which
    /// level to start the traceback.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_traceback
    pub fn traceback(lua: *Lua, state: *Lua, msg: ?[:0]const u8, level: i32) void {
        c.luaL_traceback(@ptrCast(lua), @ptrCast(state), if (msg) |message| message.ptr else null, level);
    }

    /// Raises a type error for the argument `arg` of the C function that called it.
    /// `type_name` is the name of the expected type.
    ///
    /// Only available in Lua 5.4
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `explained in text / on purpose`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_typeerror
    pub fn typeError(lua: *Lua, arg: i32, type_name: [:0]const u8) noreturn {
        _ = c.luaL_typeerror(@as(*LuaState, @ptrCast(lua)), arg, type_name.ptr);
        unreachable;
    }

    /// Returns the name of the type of the value at the given `index`
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_typename
    pub fn typeNameIndex(lua: *Lua, index: i32) [:0]const u8 {
        return std.mem.span(c.luaL_typename(@as(*LuaState, @ptrCast(lua)), index));
    }

    fn unrefLua(lua: *Lua, index: i32, r: i32) void {
        c.luaL_unref(@ptrCast(lua), index, r);
    }

    fn unrefLuau(lua: *Lua, r: i32) void {
        c.lua_unref(@ptrCast(lua), r);
    }

    /// Releases the reference `r` from the table at index `index`.
    ///
    /// The entry is removed from the table, so that the referred object can be collected. The
    /// reference ref is also freed to be used again.
    ///
    /// If ref is `ref_no` or `ref_nil`, `Lua.unref()` does nothing.
    ///
    /// Luau does not support the index parameter.
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `never`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_unref
    pub const unref = if (lang == .luau) unrefLuau else unrefLua;

    /// Pushes onto the stack a string identifying the current position of the control
    /// at the call stack `level`
    ///
    /// Typically this string has the following format: `chunkname:currentline:`
    ///
    /// Level 0 is the running function, level 1 is the function that called the
    /// running function, etc. This function is used to build a prefix for error messages.
    ///
    /// * Pops:   `0`
    /// * Pushes: `1`
    /// * Errors: `memory`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_where
    pub fn where(lua: *Lua, level: i32) void {
        c.luaL_where(@ptrCast(lua), level);
    }

    // Standard library loading functions

    /// Open all standard libraries
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_openlibs
    pub fn openLibs(lua: *Lua) void {
        c.luaL_openlibs(@ptrCast(lua));
    }

    /// Open the basic standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openBase(lua: *Lua) void {
        lua.requireF("_G", c.luaopen_base, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the coroutine standard library
    ///
    /// Not available in Lua 5.1 and LuaJIT
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openCoroutine(lua: *Lua) void {
        lua.requireF(c.LUA_COLIBNAME, c.luaopen_coroutine, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the package standard library
    ///
    /// Not available in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openPackage(lua: *Lua) void {
        lua.requireF(c.LUA_LOADLIBNAME, c.luaopen_package, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the string standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openString(lua: *Lua) void {
        lua.requireF(c.LUA_STRLIBNAME, c.luaopen_string, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the UTF-8 standard library
    ///
    /// Not available in Lua 5.1, 5.2, and LuaJIT
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openUtf8(lua: *Lua) void {
        lua.requireF(c.LUA_UTF8LIBNAME, c.luaopen_utf8, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the table standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openTable(lua: *Lua) void {
        lua.requireF(c.LUA_TABLIBNAME, c.luaopen_table, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the math standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openMath(lua: *Lua) void {
        lua.requireF(c.LUA_MATHLIBNAME, c.luaopen_math, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the io standard library
    ///
    /// Not available in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openIO(lua: *Lua) void {
        lua.requireF(c.LUA_IOLIBNAME, c.luaopen_io, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the os standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openOS(lua: *Lua) void {
        lua.requireF(c.LUA_OSLIBNAME, c.luaopen_os, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the debug standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openDebug(lua: *Lua) void {
        lua.requireF(c.LUA_DBLIBNAME, c.luaopen_debug, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the bit32 standard library
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openBit32(lua: *Lua) void {
        lua.requireF(c.LUA_BITLIBNAME, c.luaopen_bit32, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Open the vector standard library
    ///
    /// Only available in Luau
    ///
    /// * Pops:   `0`
    /// * Pushes: `0`
    /// * Errors: `other`
    pub fn openVector(lua: *Lua) void {
        lua.requireF(c.LUA_VECLIBNAME, c.luaopen_vector, true);
        if (lang == .lua52 or lang == .lua53 or lang == .lua54) lua.pop(1);
    }

    /// Returns if given typeinfo is a string type
    fn isTypeString(typeinfo: std.builtin.Type.Pointer) bool {
        const childinfo = @typeInfo(typeinfo.child);
        if (typeinfo.child == u8 and typeinfo.size != .one) {
            return true;
        } else if (typeinfo.size == .one and childinfo == .array and childinfo.array.child == u8) {
            return true;
        }
        return false;
    }

    /// Pushes any string type
    fn pushAnyString(lua: *Lua, value: anytype) !void {
        const info = @typeInfo(@TypeOf(value)).pointer;
        switch (info.size) {
            .one => {
                const childinfo = @typeInfo(info.child).array;
                std.debug.assert(childinfo.child == u8);
                std.debug.assert(childinfo.sentinel() != null);

                if (childinfo.sentinel()) |sentinel| {
                    if (sentinel != 0) {
                        @compileError("Sentinel of slice must be a null terminator");
                    }
                }
                _ = lua.pushStringZ(value);
            },
            .c, .many, .slice => {
                std.debug.assert(info.child == u8);
                if (info.sentinel()) |sentinel| {
                    if (sentinel != 0) {
                        @compileError("Sentinel of slice must be a null terminator");
                    }
                    _ = lua.pushStringZ(value);
                } else {
                    const null_terminated = try lua.allocator().dupeZ(u8, value);
                    defer lua.allocator().free(null_terminated);
                    _ = lua.pushStringZ(null_terminated);
                }
            },
        }
    }

    /// Pushes any valid zig value onto the stack,
    /// Works with ints, floats, booleans, structs,
    /// tagged unions, optionals, and strings
    pub fn pushAny(lua: *Lua, value: anytype) !void {
        switch (@typeInfo(@TypeOf(value))) {
            .int, .comptime_int => {
                lua.pushInteger(@intCast(value));
            },
            .float, .comptime_float => {
                lua.pushNumber(@floatCast(value));
            },
            .pointer => |info| {
                if (comptime isTypeString(info)) {
                    try lua.pushAnyString(value);
                } else switch (info.size) {
                    .one => {
                        if (info.is_const) {
                            @compileLog(value);
                            @compileLog("Lua cannot guarantee that references will not be modified");
                            @compileError("Pointer must not be const");
                        }
                        lua.pushLightUserdata(@ptrCast(value));
                    },
                    .c, .many, .slice => {
                        lua.createTable(0, 0);
                        for (value, 0..) |index_value, i| {
                            try lua.pushAny(i + 1);
                            try lua.pushAny(index_value);
                            lua.setTable(-3);
                        }
                    },
                }
            },
            .array => {
                lua.createTable(0, 0);
                for (value, 0..) |index_value, i| {
                    try lua.pushAny(i + 1);
                    try lua.pushAny(index_value);
                    lua.setTable(-3);
                }
            },
            .vector => |info| {
                try lua.pushAny(@as([info.len]info.child, value));
            },
            .bool => {
                lua.pushBoolean(value);
            },
            .@"enum" => {
                _ = lua.pushStringZ(@tagName(value));
            },
            .optional, .null => {
                if (value == null) {
                    lua.pushNil();
                } else {
                    try lua.pushAny(value.?);
                }
            },
            .@"struct" => |info| {
                lua.createTable(0, 0);
                inline for (info.fields) |field| {
                    try lua.pushAny(field.name);
                    try lua.pushAny(@field(value, field.name));
                    lua.setTable(-3);
                }
            },
            .@"union" => |info| {
                if (info.tag_type == null) @compileError("Parameter type is not a tagged union");
                lua.createTable(0, 0);
                errdefer lua.pop(1);
                try lua.pushAnyString(@tagName(value));

                inline for (info.fields) |field| {
                    if (std.mem.eql(u8, field.name, @tagName(value))) {
                        try lua.pushAny(@field(value, field.name));
                    }
                }
                lua.setTable(-3);
            },
            .@"fn" => {
                lua.autoPushFunction(value);
            },
            .void => {
                lua.createTable(0, 0);
            },
            else => {
                @compileLog(value);
                @compileError("Invalid type given");
            },
        }
    }

    /// Converts the specified index of the lua stack to the specified
    /// type if possible and returns it
    /// Allocates memory if necessary
    pub fn toAnyAlloc(lua: *Lua, comptime T: type, index: i32) !Parsed(T) {
        var parsed = Parsed(T){
            .arena = try lua.allocator().create(std.heap.ArenaAllocator),
            .value = undefined,
        };
        errdefer lua.allocator().destroy(parsed.arena);
        parsed.arena.* = std.heap.ArenaAllocator.init(lua.allocator());
        errdefer parsed.arena.deinit();

        parsed.value = try lua.toAnyInternal(T, parsed.arena.allocator(), true, index);

        return parsed;
    }

    /// Converts the specified index of the lua stack to the specified
    /// type if possible and returns it
    /// Does not allocate any memory, if memory allocation is needed (such as for parsing slices)
    /// use toAnyAlloc
    pub inline fn toAny(lua: *Lua, comptime T: type, index: i32) !T {
        return lua.toAnyInternal(T, null, false, index);
    }

    /// Converts the specified index of the lua stack to the specified
    /// type if possible and returns it
    /// optional allocator
    fn toAnyInternal(lua: *Lua, comptime T: type, a: ?std.mem.Allocator, comptime allow_alloc: bool, index: i32) !T {
        const stack_size_on_entry = lua.getTop();
        defer {
            if (lua.getTop() != stack_size_on_entry) {
                std.debug.print("Type that filed to parse was: {any}\n", .{T});
                std.debug.print("Expected stack size: {}, Actual Stack Size: {}\n\n", .{ stack_size_on_entry, lua.getTop() });
                @panic("internal parsing error");
            }
        }

        switch (@typeInfo(T)) {
            .int => {
                const result = try lua.toInteger(index);
                return @as(T, @intCast(result));
            },
            .float => {
                const result = try lua.toNumber(index);
                return @as(T, @floatCast(result));
            },
            .array, .vector => {
                const child = std.meta.Child(T);
                const arr_len = switch (@typeInfo(T)) {
                    inline else => |i| i.len,
                };
                var result: T = undefined;
                lua.pushValue(index);
                defer lua.pop(1);

                for (0..arr_len) |i| {
                    if (lua.getMetaField(-1, "__index")) |_| {
                        lua.pushValue(-2);
                        lua.pushInteger(@intCast(i + 1));
                        lua.call(.{ .args = 1, .results = 1 });
                    } else |_| {
                        _ = lua.rawGetIndex(-1, @intCast(i + 1));
                    }
                    defer lua.pop(1);
                    result[i] = try lua.toAny(child, -1);
                }
                return result;
            },
            .pointer => |info| {
                if (comptime isTypeString(info)) {
                    const string: [*:0]const u8 = try lua.toString(index);
                    const end = std.mem.indexOfSentinel(u8, 0, string);

                    if (!info.is_const) {
                        if (!allow_alloc) {
                            @compileError("toAny cannot allocate memory, try using toAnyAlloc");
                        }

                        if (info.sentinel() != null) {
                            return try a.?.dupeZ(u8, string[0..end]);
                        } else {
                            return try a.?.dupe(u8, string[0..end]);
                        }
                    } else {
                        return if (info.sentinel() == null) string[0..end] else string[0..end :0];
                    }
                } else switch (info.size) {
                    .slice, .many => {
                        if (!allow_alloc) {
                            @compileError("toAny cannot allocate memory, try using toAnyAlloc");
                        }
                        return try lua.toSlice(info.child, a.?, index);
                    },
                    else => {
                        return try lua.toUserdata(info.child, index);
                    },
                }
            },
            .bool => {
                return lua.toBoolean(index);
            },
            .@"enum" => |info| {
                const string = try lua.toAnyInternal([]const u8, a, allow_alloc, index);
                inline for (info.fields) |enum_member| {
                    if (std.mem.eql(u8, string, enum_member.name)) {
                        return @field(T, enum_member.name);
                    }
                }
                return error.LuaInvalidEnumTagName;
            },
            .@"struct" => {
                return try lua.toStruct(T, a, allow_alloc, index);
            },
            .@"union" => |u| {
                if (u.tag_type == null) @compileError("Parameter type is not a tagged union");
                if (!lua.isTable(index)) return error.LuaValueIsNotATable;

                lua.pushValue(index);
                defer lua.pop(1);
                lua.pushNil();
                if (lua.next(-2)) {
                    defer lua.pop(2);
                    const key = try lua.toAny([]const u8, -2);
                    inline for (u.fields) |field| {
                        if (std.mem.eql(u8, key, field.name)) {
                            return @unionInit(T, field.name, try lua.toAny(field.type, -1));
                        }
                    }
                    return error.LuaInvalidTagName;
                }
                return error.LuaTableIsEmpty;
            },
            .optional => {
                if (lua.isNil(index)) {
                    return null;
                } else {
                    return try lua.toAnyInternal(@typeInfo(T).optional.child, a, allow_alloc, index);
                }
            },
            .void => {
                if (!lua.isTable(index)) return error.LuaValueIsNotATable;
                lua.pushValue(index);
                defer lua.pop(1);
                lua.pushNil();
                if (lua.next(-2)) {
                    lua.pop(2);
                    return error.LuaVoidTableIsNotEmpty;
                }
                return void{};
            },
            else => {
                @compileError("Invalid parameter type");
            },
        }
    }

    /// Converts a lua array to a zig slice, memory is owned by the caller
    fn toSlice(lua: *Lua, comptime ChildType: type, a: std.mem.Allocator, raw_index: i32) ![]ChildType {
        const index = lua.absIndex(raw_index);

        if (!lua.isTable(index)) {
            return error.LuaValueNotATable;
        }

        const size = lua.rawLen(index);
        var result = try a.alloc(ChildType, size);

        for (1..size + 1) |i| {
            _ = try lua.pushAny(i);
            _ = lua.getTable(index);
            defer lua.pop(1);
            result[i - 1] = try lua.toAnyInternal(ChildType, a, true, -1);
        }

        return result;
    }

    /// Converts value at given index to a zig struct if possible
    fn toStruct(lua: *Lua, comptime T: type, a: ?std.mem.Allocator, comptime allow_alloc: bool, raw_index: i32) !T {
        const stack_size_on_entry = lua.getTop();
        defer std.debug.assert(lua.getTop() == stack_size_on_entry);

        const index = lua.absIndex(raw_index);

        if (!lua.isTable(index)) {
            return error.LuaValueNotATable;
        }

        var result: T = undefined;

        inline for (@typeInfo(T).@"struct".fields) |field| {
            const field_type_info = comptime @typeInfo(field.type);
            const field_name = comptime field.name ++ "";
            _ = lua.pushStringZ(field_name);

            const lua_field_type = lua.getTable(index);
            defer lua.pop(1);
            if (lua_field_type == .nil) {
                if (field.defaultValue()) |default| {
                    @field(result, field.name) = default;
                } else if (field_type_info != .optional) {
                    return error.LuaTableMissingValue;
                }
            } else {
                const stack_size_before_call = lua.getTop();
                @field(result, field.name) = try lua.toAnyInternal(field.type, a, allow_alloc, -1);
                std.debug.assert(stack_size_before_call == lua.getTop());
            }
        }

        return result;
    }

    /// Calls a function and pushes its return value to the top of the stack
    fn autoCallAndPush(lua: *Lua, comptime ReturnType: type, func_name: [:0]const u8, args: anytype) !void {
        if (try lua.getGlobal(func_name) != LuaType.function) return error.LuaInvalidFunctionName;

        inline for (args) |arg| {
            try lua.pushAny(arg);
        }

        const num_results = if (ReturnType == void) 0 else 1;
        try lua.protectedCall(.{ .args = args.len, .results = num_results });
    }

    ///automatically calls a lua function with the given arguments
    pub fn autoCall(lua: *Lua, comptime ReturnType: type, func_name: [:0]const u8, args: anytype) !ReturnType {
        try lua.autoCallAndPush(ReturnType, func_name, args);
        const result = try lua.toAny(ReturnType, -1);
        lua.setTop(0);
        return result;
    }

    ///automatically calls a lua function with the given arguments
    pub fn autoCallAlloc(lua: *Lua, comptime ReturnType: type, func_name: [:0]const u8, args: anytype) !Parsed(ReturnType) {
        try lua.autoCallAndPush(ReturnType, func_name, args);
        const result = try lua.toAnyAlloc(ReturnType, -1);
        lua.setTop(0);
        return result;
    }

    //automatically generates a wrapper function
    fn GenerateInterface(comptime function: anytype) type {
        const info = @typeInfo(@TypeOf(function));
        if (info != .@"fn") {
            @compileLog(info);
            @compileLog(function);
            @compileError("function pointer must be passed");
        }
        return struct {
            pub fn interface(lua: *Lua) i32 {
                var parameters: std.meta.ArgsTuple(@TypeOf(function)) = undefined;

                inline for (info.@"fn".params, 0..) |param, i| {
                    const param_info = @typeInfo(param.type.?);
                    //only use the overhead of creating the arena allocator if needed
                    if (comptime param_info == .pointer and param_info.pointer.size != .One) {
                        const parsed = lua.toAnyAlloc(param.type.?, (i + 1)) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };

                        defer parsed.deinit();

                        parameters[i] = parsed.value;
                    } else {
                        const parsed = lua.toAny(param.type.?, (i + 1)) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };

                        parameters[i] = parsed;
                    }
                }

                if (@typeInfo(info.@"fn".return_type.?) == .error_union) {
                    const result = @call(.auto, function, parameters) catch |err| {
                        lua.raiseErrorStr(@errorName(err), .{});
                    };
                    lua.pushAny(result) catch |err| {
                        lua.raiseErrorStr(@errorName(err), .{});
                    };
                } else {
                    const result = @call(.auto, function, parameters);
                    lua.pushAny(result) catch |err| {
                        lua.raiseErrorStr(@errorName(err), .{});
                    };
                }

                return 1;
            }
        };
    }

    ///generates the interface for and pushes a function to the stack
    pub fn autoPushFunction(lua: *Lua, function: anytype) void {
        const Interface = GenerateInterface(function);
        lua.pushFunction(wrap(Interface.interface));
    }

    ///get any lua global
    pub fn get(lua: *Lua, comptime ReturnType: type, name: [:0]const u8) !ReturnType {
        _ = try lua.getGlobal(name);
        return try lua.toAny(ReturnType, -1);
    }

    /// get any lua global
    /// can allocate memory
    pub fn getAlloc(lua: *Lua, comptime ReturnType: type, name: [:0]const u8) !Parsed(ReturnType) {
        _ = try lua.getGlobal(name);
        return try lua.toAnyAlloc(ReturnType, -1);
    }

    ///set any lua global
    pub fn set(lua: *Lua, name: [:0]const u8, value: anytype) !void {
        try lua.pushAny(value);
        lua.setGlobal(name);
    }
};

/// A string buffer allowing for Zig code to build Lua strings piecemeal
/// All LuaBuffer functions are wrapped in this struct to make the API more convenient to use
pub const Buffer = struct {
    b: LuaBuffer = undefined,

    /// Initialize a Lua string buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_buffinit
    pub fn init(buf: *Buffer, lua: *Lua) void {
        c.luaL_buffinit(@ptrCast(lua), &buf.b);
    }

    /// Initialize a Lua string buffer with an initial size
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_buffinitsize
    pub fn initSize(buf: *Buffer, lua: *Lua, size: usize) []u8 {
        return c.luaL_buffinitsize(@ptrCast(lua), &buf.b, size)[0..size];
    }

    /// Internal Lua type for a string buffer
    pub const LuaBuffer = c.luaL_Buffer;

    pub const buffer_size = if (lang == .luau) c.LUA_BUFFERSIZE else c.LUAL_BUFFERSIZE;

    /// Adds `byte` to the buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_addchar
    pub fn addChar(buf: *Buffer, byte: u8) void {
        // could not be translated by translate-c
        var lua_buf = &buf.b;

        switch (lang) {
            .lua51, .luajit, .luau => {
                if (lua_buf.p > &lua_buf.buffer[buffer_size - 1]) _ = buf.prep();
                lua_buf.p.* = byte;
                lua_buf.p += 1;
            },
            else => {
                if (lua_buf.n >= lua_buf.size) _ = buf.prepSize(1);
                lua_buf.b[lua_buf.n] = byte;
                lua_buf.n += 1;
            },
        }
    }

    /// Adds a copy of the string `str` to the buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_addgsub
    pub fn addGSub(buf: *Buffer, str: [:0]const u8, pat: [:0]const u8, rep: [:0]const u8) void {
        c.luaL_addgsub(&buf.b, str.ptr, pat.ptr, rep.ptr);
    }

    /// Adds the string to the buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_addlstring
    pub fn addString(buf: *Buffer, str: []const u8) void {
        c.luaL_addlstring(&buf.b, str.ptr, str.len);
    }

    /// Adds to the buffer a string of `length` previously copied to the buffer area
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_addsize
    pub fn addSize(buf: *Buffer, length: usize) void {
        // another function translate-c couldn't handle
        // c.luaL_addsize(&buf.b, length);
        var lua_buf = &buf.b;

        switch (lang) {
            .lua51, .luajit, .luau => lua_buf.p += length,
            else => lua_buf.n += length,
        }
    }

    /// Adds the zero-terminated string pointed to by `str` to the buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_addstring
    pub fn addStringZ(buf: *Buffer, str: [:0]const u8) void {
        switch (lang) {
            .luau => c.luaL_addlstring(&buf.b, str.ptr, str.len),
            else => c.luaL_addstring(&buf.b, str.ptr),
        }
    }

    /// Adds the value on the top of the stack to the buffer
    /// Pops the value
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_addvalue
    pub fn addValue(buf: *Buffer) void {
        c.luaL_addvalue(&buf.b);
    }

    /// Adds the value at the given index to the buffer
    pub fn addValueAny(buf: *Buffer, idx: i32) void {
        c.luaL_addvalueany(&buf.b, idx);
    }

    /// Returns a slice of the current content of the buffer
    /// Any changes to the buffer may invalidate this slice
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_buffaddr
    pub fn addr(buf: *Buffer) []u8 {
        const length = buf.b.n;
        return c.luaL_buffaddr(&buf.b)[0..length];
    }

    /// Returns the length of the buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_bufflen
    pub fn len(buf: *Buffer) usize {
        return c.luaL_bufflen(&buf.b);
    }

    /// Removes `num` bytes from the buffer
    /// TODO: perhaps error check?
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_buffsub
    pub fn sub(buf: *Buffer, num: usize) void {
        // Another bug with translate-c
        // c.luaL_buffsub(&buf.b, num);
        var lua_buf = &buf.b;
        lua_buf.n -= num;
    }

    /// Equivalent to prepSize with a buffer size of Buffer.buffer_size
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_prepbuffer
    pub fn prep(buf: *Buffer) []u8 {
        return switch (lang) {
            .luau => c.luaL_prepbuffsize(&buf.b, buffer_size)[0..buffer_size],
            else => c.luaL_prepbuffer(&buf.b)[0..buffer_size],
        };
    }

    /// Returns an address to a space of `size` where you can copy a string
    /// to be added to the buffer
    /// you must call `Buffer.addSize` to actually add it to the buffer
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_prepbuffsize
    pub fn prepSize(buf: *Buffer, size: usize) []u8 {
        return c.luaL_prepbuffsize(&buf.b, size)[0..size];
    }

    /// Finishes the use of the buffer leaving the final string on the top of the stack
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_pushresult
    pub fn pushResult(buf: *Buffer) void {
        c.luaL_pushresult(&buf.b);
    }

    /// Equivalent to `Buffer.addSize()` followed by `Buffer.pushResult()`
    /// See https://www.lua.org/manual/5.4/manual.html#luaL_pushresultsize
    pub fn pushResultSize(buf: *Buffer, size: usize) void {
        c.luaL_pushresultsize(&buf.b, size);
    }
};

// Helper functions to make the ziglua API easier to use

const Tuple = std.meta.Tuple;

fn TypeOfWrap(comptime function: anytype) type {
    const Args = std.meta.ArgsTuple(@TypeOf(function));
    return switch (Args) {
        Tuple(&.{*Lua}) => CFn,
        Tuple(&.{ *Lua, Event, *DebugInfo }) => CHookFn,
        Tuple(&.{ *Lua, Status, Context }) => CContFn,
        Tuple(&.{ *Lua, *anyopaque }) => CReaderFn,
        Tuple(&.{*anyopaque}) => CUserdataDtorFn,
        Tuple(&.{ *Lua, i32 }) => CInterruptCallbackFn,
        Tuple(&.{[]const u8}) => CUserAtomCallbackFn,
        Tuple(&.{ ?*anyopaque, []const u8, bool }) => CWarnFn,
        Tuple(&.{ *Lua, []const u8, *anyopaque }) => CWriterFn,
        else => @compileError("Unsupported function given to wrap '" ++ @typeName(@TypeOf(function)) ++ "'"),
    };
}

/// Wraps the given Zig function for use in the Lua API
///
/// * Wraps `fn (lua: *Lua) i32` as `CFn`
/// * Wraps `fn (lua: *Lua, event: Event, info: *DebugInfo) void` as `CHookFn`
/// * Wraps `fn (lua: *Lua, status: Status, ctx: Context) i32` as 'CContFn'
/// * Wraps `fn (lua: *Lua, data: *anyopaque) ?[]const u8` as `CReaderFn`
/// * Wraps `fn (data: *anyopaque) void` as `CUserdataDtorFn`
/// * Wraps `fn (lua: *Lua, gc: i32) void` as `CInterruptCallbackFn`
/// * Wraps `fn (str: []const u8) i16` as `CUserAtomCallbackFn`
/// * Wraps `fn (data: ?*anyopaque, msg: []const u8, to_cont: bool) void` as `CWarnFn`
/// * Wraps `fn (lua: *Lua, buf: []const u8, data: *anyopaque) bool` as `CWriterFn`
///
/// Functions that accept a `*Lua` pointer also support returning error unions. For example,
/// wrap also supports `fn (lua: *Lua) !i32` for a `CFn`.
pub fn wrap(comptime function: anytype) TypeOfWrap(function) {
    const info = @typeInfo(@TypeOf(function));
    if (info != .@"fn") {
        @compileError("Wrap only accepts functions");
    }

    const has_error_union = @typeInfo(info.@"fn".return_type.?) == .error_union;

    const Args = std.meta.ArgsTuple(@TypeOf(function));
    switch (Args) {
        // CFn
        Tuple(&.{*Lua}) => {
            return struct {
                fn inner(state: ?*LuaState) callconv(.C) c_int {
                    // this is called by Lua, state should never be null
                    var lua: *Lua = @ptrCast(state.?);
                    if (has_error_union) {
                        return @call(.always_inline, function, .{lua}) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };
                    } else {
                        return @call(.always_inline, function, .{lua});
                    }
                }
            }.inner;
        },
        // CHookFn
        Tuple(&.{ *Lua, Event, *DebugInfo }) => {
            return struct {
                fn inner(state: ?*LuaState, ar: ?*Debug) callconv(.C) void {
                    // this is called by Lua, state should never be null
                    var lua: *Lua = @ptrCast(state.?);
                    var debug_info: DebugInfo = .{
                        .current_line = if (ar.?.currentline == -1) null else ar.?.currentline,
                        .private = switch (lang) {
                            .lua51, .luajit => ar.?.i_ci,
                            else => @ptrCast(ar.?.i_ci),
                        },
                    };
                    if (has_error_union) {
                        @call(.always_inline, function, .{ lua, @as(Event, @enumFromInt(ar.?.event)), &debug_info }) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };
                    } else {
                        @call(.always_inline, function, .{ lua, @as(Event, @enumFromInt(ar.?.event)), &debug_info });
                    }
                }
            }.inner;
        },
        // CContFn
        Tuple(&.{ *Lua, Status, Context }) => {
            return struct {
                fn inner(state: ?*LuaState, status: c_int, ctx: Context) callconv(.C) c_int {
                    // this is called by Lua, state should never be null
                    var lua: *Lua = @ptrCast(state.?);
                    if (has_error_union) {
                        return @call(.always_inline, function, .{ lua, @as(Status, @enumFromInt(status)), ctx }) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };
                    } else {
                        return @call(.always_inline, function, .{ lua, @as(Status, @enumFromInt(status)), ctx });
                    }
                }
            }.inner;
        },
        // CReaderFn
        Tuple(&.{ *Lua, *anyopaque }) => {
            return struct {
                fn inner(state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.C) [*c]const u8 {
                    // this is called by Lua, state should never be null
                    var lua: *Lua = @ptrCast(state.?);
                    if (has_error_union) {
                        const result = @call(.always_inline, function, .{ lua, data.? }) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };
                        if (result) |buffer| {
                            size.* = buffer.len;
                            return buffer.ptr;
                        } else {
                            size.* = 0;
                            return null;
                        }
                    } else {
                        if (@call(.always_inline, function, .{ lua, data.? })) |buffer| {
                            size.* = buffer.len;
                            return buffer.ptr;
                        } else {
                            size.* = 0;
                            return null;
                        }
                    }
                }
            }.inner;
        },
        // CUserdataDtorFn
        Tuple(&.{*anyopaque}) => {
            return struct {
                fn inner(userdata: *anyopaque) callconv(.C) void {
                    return @call(.always_inline, function, .{userdata});
                }
            }.inner;
        },
        // CInterruptCallbackFn
        Tuple(&.{ *Lua, i32 }) => {
            return struct {
                fn inner(state: ?*LuaState, gc: c_int) callconv(.C) void {
                    // this is called by Lua, state should never be null
                    var lua: *Lua = @ptrCast(state.?);
                    if (has_error_union) {
                        @call(.always_inline, function, .{ lua, gc }) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };
                    } else {
                        @call(.always_inline, function, .{ lua, gc });
                    }
                }
            }.inner;
        },
        // CUserAtomCallbackFn
        Tuple(&.{[]const u8}) => {
            return struct {
                fn inner(str: [*c]const u8, len: usize) callconv(.C) i16 {
                    if (str) |s| {
                        const buf = s[0..len];
                        return @call(.always_inline, function, .{buf});
                    }
                    return -1;
                }
            }.inner;
        },
        // CWarnFn
        Tuple(&.{ ?*anyopaque, []const u8, bool }) => {
            return struct {
                fn inner(data: ?*anyopaque, msg: [*c]const u8, to_cont: c_int) callconv(.C) void {
                    // warning messages emitted from Lua should be null-terminated for display
                    const message = std.mem.span(@as([*:0]const u8, @ptrCast(msg)));
                    @call(.always_inline, function, .{ data, message, to_cont != 0 });
                }
            }.inner;
        },
        // CWriterFn
        Tuple(&.{ *Lua, []const u8, *anyopaque }) => {
            return struct {
                fn inner(state: ?*LuaState, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.C) c_int {
                    // this is called by Lua, state should never be null
                    var lua: *Lua = @ptrCast(state.?);
                    const buffer = @as([*]const u8, @ptrCast(buf))[0..size];

                    const result = if (has_error_union) blk: {
                        break :blk @call(.always_inline, function, .{ lua, buffer, data.? }) catch |err| {
                            lua.raiseErrorStr(@errorName(err), .{});
                        };
                    } else blk: {
                        break :blk @call(.always_inline, function, .{ lua, buffer, data.? });
                    };

                    // it makes more sense for the inner writer function to return false for failure,
                    // so negate the result here
                    return @intFromBool(!result);
                }
            }.inner;
        },
        else => @compileError("Unsupported function given to wrap '" ++ @typeName(@TypeOf(function)) ++ "'"),
    }
}

/// Zig wrapper for Luau lua_CompileOptions that uses the same defaults as Luau if
/// no compile options is specified.
pub const CompileOptions = struct {
    /// 0. no optimization
    /// 1. baseline optimization level that doesn't prevent debuggability
    /// 2. includes optimizations that harm debuggability such as inlining
    optimization_level: i32 = 1,

    /// 0. no debugging support
    /// 1. line info & function names only; sufficient for backtraces
    /// 2. full debug info with local & upvalue names; necessary for debugger
    debug_level: i32 = 1,

    /// type information is used to guide native code generation decisions
    /// information includes testable types for function arguments, locals, upvalues and some temporaries
    ///
    /// 0. generate for native modules
    /// 1. generate for all modules
    type_info_level: i32 = 0,

    /// 0. no code coverage support
    /// 1. statement coverage
    /// 2. statement and expression coverage (verbose)
    coverage_level: i32 = 0,

    /// alternative global builtin to construct vectors, in addition to default builtin 'vector.create'
    vector_lib: ?[*:0]const u8 = null,
    vector_ctor: ?[*:0]const u8 = null,

    /// alternative vector type name for type tables, in addition to default type 'vector'
    vector_type: ?[*:0]const u8 = null,

    /// null-terminated array of globals that are mutable; disables the import optimization for fields accessed through these
    mutable_globals: ?[*:null]const ?[*:0]const u8 = null,

    /// null-terminated array of userdata types that will be included in the type information
    userdata_types: ?[*:null]const ?[*:0]const u8 = null,
};

/// Compile luau source into bytecode, return callee owned buffer allocated through the given allocator.
pub fn compile(allocator: Allocator, source: []const u8, options: CompileOptions) ![]const u8 {
    var size: usize = 0;

    var opts = c.lua_CompileOptions{
        .optimizationLevel = options.optimization_level,
        .debugLevel = options.debug_level,
        .typeInfoLevel = options.type_info_level,
        .coverageLevel = options.coverage_level,
        .vectorLib = options.vector_lib,
        .vectorCtor = options.vector_ctor,
        .mutableGlobals = options.mutable_globals,
        .userdataTypes = options.userdata_types,
    };
    const bytecode = c.luau_compile(source.ptr, source.len, &opts, &size);
    if (bytecode == null) return error.OutOfMemory;
    defer zig_luau_free(bytecode);
    return try allocator.dupe(u8, bytecode[0..size]);
}

/// Export a Zig function to be used as a the entry point to a Lua module
///
/// Exported as luaopen_[name]
pub fn exportFn(comptime name: []const u8, comptime func: anytype) CFn {
    if (lang == .luau) @compileError("Luau does not support compiling or loading shared modules");

    return struct {
        fn luaopen(state: ?*LuaState) callconv(.C) c_int {
            const declaration = comptime wrap(func);

            return @call(.always_inline, declaration, .{state});
        }

        comptime {
            @export(&luaopen, .{ .name = "luaopen_" ++ name });
        }
    }.luaopen;
}
