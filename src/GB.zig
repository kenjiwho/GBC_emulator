const GB = @This();

const std = @import("std");
const CPU = @import("CPU.zig");
const MMIO = @import("MMIO.zig");

screen: [160 * 144]u8 = @splat(0), // 160x144 pixels
cpu: CPU = undefined, // cpu
mmio: MMIO = MMIO.init(), // memory-mapped I/O

pub fn init() GB {
    var gb = GB{};

    gb.cpu = CPU.init(&gb.mmio);

    return gb;
}

pub fn step(self: *GB) void {
    self.cpu.execute();
    self.cpu.regs.PC +%= 1;
}
