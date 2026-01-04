//! This module defines the CPU registers
const Registers = @This();

// AF
A: u8 = 0, // Accumulator
F: u8 = 0, // Flags
// BC
B: u8 = 0,
C: u8 = 0,
// DE
D: u8 = 0,
E: u8 = 0,
// HL
H: u8 = 0,
L: u8 = 0,
SP: u16 = 0, // Stack Pointer
PC: u16 = 0, // Program Counter

pub const Flag = enum(u3) {
    Z = 7, // Zero Flag
    N = 6, // Subtract Flag
    H = 5, // Half Carry Flag
    C = 4, // Carry Flag
};

pub fn init() Registers {
    return Registers{};
}

// access registers as 16-bit pairs
pub fn getBC(self: *const Registers) u16 {
    return (@as(u16, self.B) << 8) | self.C;
}

pub fn setBC(self: *Registers, value: u16) void {
    self.B = @intCast(value >> 8);
    self.C = @intCast(value & 0xFF);
}

pub fn getDE(self: *const Registers) u16 {
    return (@as(u16, self.D) << 8) | self.E;
}

pub fn setDE(self: *Registers, value: u16) void {
    self.D = @intCast(value >> 8);
    self.E = @intCast(value & 0xFF);
}

pub fn getHL(self: *const Registers) u16 {
    return (@as(u16, self.H) << 8) | self.L;
}

pub fn setHL(self: *Registers, value: u16) void {
    self.H = @intCast(value >> 8);
    self.L = @intCast(value & 0xFF);
}

pub fn getAF(self: *const Registers) u16 {
    return (@as(u16, self.A) << 8) | self.F;
}

pub fn setAF(self: *Registers, value: u16) void {
    self.A = @intCast(value >> 8);
    self.F = @intCast(value & 0xF0);
}
