const std = @import("std");
const GB = @import("GB.zig");

pub fn main() !void {
    var gb = GB.init();

    std.debug.print("{d}\n", .{gb.cpu.regs.PC});

    gb.step();

    std.debug.print("{d}\n", .{gb.cpu.regs.PC});
}

test {
    _ = @import("CPU.zig");
}

test "context" {
    var gb = GB.init();
    gb.step();

    try std.testing.expect(gb.cpu.regs.PC == 1);
}
