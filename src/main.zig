const std = @import("std");
const GB = @import("GB.zig");

pub fn main() !void {
    var gb = GB.init();

    std.debug.print("{d}\n", .{gb.cpu.registers.PC});

    gb.cycle();

    std.debug.print("{d}\n", .{gb.cpu.registers.PC});
}

test {
    _ = @import("CPU.zig");
}

test "context" {
    var gb = GB.init();
    gb.cycle();

    try std.testing.expect(gb.cpu.registers.PC == 1);
}
