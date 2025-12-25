//! Multi threaded lua program
//! The additional header must be passed to the build using `-Dlua_user_h=examples/user.h`
//! Checkout http://lua-users.org/wiki/ThreadsTutorial for more info

const std = @import("std");
const zlua = @import("zlua");

var mutex = std.Thread.Mutex{};

export fn lua_zlock(L: *zlua.LuaState) callconv(.c) void {
    _ = L;
    mutex.lock();
}

export fn lua_zunlock(L: *zlua.LuaState) callconv(.c) void {
    _ = L;
    mutex.unlock();
}

fn add_to_x(lua: *zlua.Lua, num: usize) void {
    for (0..num) |_| {
        // omit error handling for brevity
        lua.loadString("x = x + 1\n") catch return;
        lua.protectedCall(.{}) catch return;
    }

    const size = 256;
    var buf = [_:0]u8{0} ** size;
    _ = std.fmt.bufPrint(&buf, "print(\"{}: \", x)", .{std.Thread.getCurrentId()}) catch return;

    // The printing from different threads does not always work nicely
    // There seems to be a separate sterr lock on each argument to print
    lua.loadString(&buf) catch return;
    lua.protectedCall(.{}) catch return;
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize The Lua vm and get a reference to the main thread
    var lua = try zlua.Lua.init(allocator);
    defer lua.deinit();

    lua.openLibs();

    // create a global variable accessible by all threads
    // omit error handling for brevity
    try lua.loadString("_G.x = 0\n");
    try lua.protectedCall(.{});

    const num = 1_000;
    const n_jobs = 5;
    var subs: [n_jobs]*zlua.Lua = undefined;

    // create a thread pool to run all the functions
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator, .n_jobs = n_jobs });
    defer pool.deinit();

    var wg: std.Thread.WaitGroup = .{};

    for (0..n_jobs) |i| {
        subs[i] = lua.newThread();
        pool.spawnWg(&wg, add_to_x, .{ subs[i], num });
    }

    // also do the thing from the main thread
    add_to_x(lua, num);

    wg.wait();

    for (subs) |sub| {
        try lua.closeThread(sub);
    }

    // print the final value
    try lua.loadString("print(x)\n");
    try lua.protectedCall(.{});
}
