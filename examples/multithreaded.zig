//! Multi threaded lua program
//! The additional header must be passed to the build using `-Dlua_user_h=examples/user.h`
//! Checkout http://lua-users.org/wiki/ThreadsTutorial for more info

const std = @import("std");
const zlua = @import("zlua");

var mutex = std.Io.Mutex.init;
var io: std.Io = undefined;

export fn lua_zlock(L: *zlua.LuaState) callconv(.c) void {
    _ = L;
    mutex.lock(io) catch {};
}

export fn lua_zunlock(L: *zlua.LuaState) callconv(.c) void {
    _ = L;
    mutex.unlock(io);
}

fn add_to_x(lua: *zlua.Lua, num: usize) void {
    for (0..num) |_| {
        // omit error handling for brevity
        lua.loadString("x = x + 1\n") catch return;
        lua.protectedCall(.{}) catch return;
    }

    const size = 256;
    var buf = std.mem.zeroes([size:0]u8);
    _ = std.fmt.bufPrint(&buf, "print(\"{}: \", x)", .{std.Thread.getCurrentId()}) catch return;

    // The printing from different threads does not always work nicely
    // There seems to be a separate sterr lock on each argument to print
    lua.loadString(&buf) catch return;
    lua.protectedCall(.{}) catch return;
}

pub fn main(init: std.process.Init) anyerror!void {
    const gpa = init.gpa;
    io = init.io;

    // Initialize The Lua vm and get a reference to the main thread
    var lua = try zlua.Lua.init(gpa);
    defer lua.deinit();

    lua.openLibs();

    // create a global variable accessible by all threads
    // omit error handling for brevity
    try lua.loadString("_G.x = 0\n");
    try lua.protectedCall(.{});

    const num = 1_000;
    const n_jobs = 5;
    var subs: [n_jobs]*zlua.Lua = undefined;

    // create a wait group to run all the functions
    var wg = std.Io.Group.init;

    for (0..n_jobs) |i| {
        subs[i] = lua.newThread();
        wg.async(io, add_to_x, .{ subs[i], num });
    }

    // also do the thing from the main thread
    add_to_x(lua, num);

    try wg.await(io);

    for (subs) |sub| {
        try lua.closeThread(sub);
    }

    // print the final value
    try lua.loadString("print(x)\n");
    try lua.protectedCall(.{});
}
