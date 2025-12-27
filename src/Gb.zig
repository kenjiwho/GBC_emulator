const Gb = @This();

const std = @import("std");
const instructions = @import("cpu_instructions.zig");

RAM: [0x8000]u8 = @splat(0), // 32KiB RAM
vRAM: [0x4000]u8 = @splat(0), // 16KiB vRAM
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels
registers: [8]u8 = @splat(0), // 8x8-bit registers or 4x16-bit registers (AF, BC, DE, HL)
pc: u16 = 0, // 16-bit program counter
sp: u16 = 0, // 16-bit stack pointer

pub const NOP = instructions.NOP;
pub const LD_r16_imm16 = instructions.LD_r16_imm16;
pub const LD_r16mem_A = instructions.LD_r16mem_A;
pub const LD_A_r16mem = instructions.LD_A_r16mem;
pub const LD_imm16_SP = instructions.LD_imm16_SP;
pub const INC_r16 = instructions.INC_r16;
pub const DEC_r16 = instructions.DEC_r16;
pub const ADD_HL_r16 = instructions.ADD_HL_r16;
