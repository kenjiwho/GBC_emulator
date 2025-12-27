const GB = @This();

const std = @import("std");
const CPU = @import("CPU.zig");
const Context = @import("Context.zig");

RAM: [0x8000]u8 = @splat(0), // 32KiB RAM
vRAM: [0x4000]u8 = @splat(0), // 16KiB vRAM
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels
cpu: CPU = CPU.init(), // 8x8-bit registers or 4x16-bit registers (AF, BC, DE, HL) + stack pointer + program counter

pub fn init() GB {
    return GB{};
}

pub fn cycle(self: *GB) void {
    const ctx = Context{
        .regs = &self.cpu.registers,
        .RAM = &self.RAM,
        .pc = &self.cpu.registers.PC,
        .sp = &self.cpu.registers.SP,
    };

    self.cpu.execute(ctx);
}
