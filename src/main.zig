const std = @import("std");
const GB = @import("GB.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gb = try GB.init(allocator);
    defer gb.deinit(allocator);

    std.debug.print("{d}\n", .{gb.cpu.regs.PC});

    gb.step();

    std.debug.print("{d}\n", .{gb.cpu.regs.PC});
}

test {
    _ = @import("CPU.zig");
}

test "context" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gb = try GB.init(allocator);
    defer gb.deinit(allocator);

    gb.step();

    try std.testing.expectEqual(1, gb.cpu.regs.PC);
}
