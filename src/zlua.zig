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

    // Deinitialize a Lua state and free all memory
    pub fn deinit(lua: *Lua) void {
        lua.close();
        if (lua.allocator) |a| {
            const allocator = a;
            allocator.destroy(a);
            lua.allocator = null;
        }
    }

    // Library functions

    /// The type of function that Lua uses for all internal allocations and frees
    /// data is an opaque pointer to any data (the allocator), ptr is a pointer to the block being alloced/realloced/freed
    /// osize is the original size or a doce, and nsize is the new size
    ///
    /// See https://www.lua.org/manual/5.4/manual.html#lua_Alloc for more details
    pub const AllocFn = fn (data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*anyopaque;

    /// Release all Lua objects in the state and free all dynamic memory
    pub fn close(lua: *Lua) void {
        c.lua_close(lua.state);
    }

    /// Creates a new independent state and returns its main thread
    pub fn newState(alloc_fn: AllocFn, data: ?*anyopaque) !Lua {
        const state = c.lua_newstate(alloc_fn, data) orelse return error.OutOfMemory;
        return Lua{ .state = state };
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

// Tests

const testing = std.testing;

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
        lua.openLibs();
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
