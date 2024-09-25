const std = @import("std");
const ziglua = @import("ziglua");

pub fn main() !void {
    const T = struct { foo: i32 };
    const MyEnum = enum { asdf, fdsa, qwer, rewq };
    const SubType = struct { foo: i32, bar: bool, bip: MyEnum, bap: ?[]MyEnum };
    const Bippity = struct { A: ?i32, B: *bool, C: []const u8, D: ?*SubType };
    const TestType = struct { a: i32, b: f32, c: bool, d: SubType, e: [10]Bippity };
    const Foo = struct { far: MyEnum, near: SubType };

    const to_define: []const ziglua.DefineEntry = &.{
        .{ .type = TestType, .name = "TestType" },
        .{ .type = Foo, .name = "Foo" },
        .{ .type = T, .name = "T" },
    };
    const output = std.mem.sliceTo(std.os.argv[1], 0);
    try ziglua.define(output, to_define);
}
