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
