const std = @import("std");
const zlua = @import("zlua");

const T = struct { foo: i32 };
const MyEnum = enum { asdf, fdsa, qwer, rewq };
const SubType = struct { foo: i32, bar: bool, bip: MyEnum, bap: ?[]MyEnum };
const Bippity = struct { A: ?i32, B: *bool, C: []const u8, D: ?*SubType };
const TestType = struct { a: i32, b: f32, c: bool, d: SubType, e: [10]Bippity };
const Foo = struct { far: MyEnum, near: SubType };

pub fn main(init: std.process.Init) !void {
    const output_file_path = std.mem.sliceTo(init.minimal.args.vector[1], 0);
    try zlua.define(init.io, std.heap.c_allocator, output_file_path, &.{ T, TestType, Foo });
}
