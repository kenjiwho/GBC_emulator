//! Context structure passed to CPU instructions
const Context = @This();

const Registers = @import("Registers.zig");

regs: *Registers,
RAM: []u8,
pc: *u16,
sp: *u16,

/// Fetches the opcode at the current PC
pub fn opcode(self: Context) u8 {
    return self.RAM[self.pc.*];
}

/// Fetches a 8-bit immediate value from the instruction stream
pub fn getImm8(self: Context) u8 {
    return self.RAM[self.pc.* + 1];
}

/// Fetches a 16-bit immediate value from the instruction stream
pub fn getImm16(self: Context) u16 {
    return (@as(u16, self.RAM[self.pc.* + 1]) << 8) | self.RAM[self.pc.* + 2];
}
