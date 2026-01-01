const GB = @This();

const std = @import("std");
const CPU = @import("CPU.zig");

RAM: [0x8000]u8 = @splat(0), // 32KiB RAM
vRAM: [0x4000]u8 = @splat(0), // 16KiB vRAM
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels
cpu: CPU = undefined, // cpu

pub fn init() GB {
    var gb = GB{};

    gb.cpu = CPU.init(gb.RAM[0..]);

    return gb;
}

pub fn cycle(self: *GB) void {
    self.cpu.execute();
    self.cpu.regs.PC += 1;
}
