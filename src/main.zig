const std = @import("std");
const App = @import("App.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    _ = args;

    var app = try App.init(io, gpa);
    defer app.deinit(gpa);
    try app.run(gpa);
}

test {
    _ = @import("tests/test_instrs.zig");
}
