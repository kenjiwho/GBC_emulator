const Gb = @This();

const std = @import("std");
const instructions = @import("cpu_instructions.zig");

RAM: [0x8000]u8 = @splat(0), // 32KiB RAM
vRAM: [0x4000]u8 = @splat(0), // 16KiB vRAM
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels
registers: [8]u8 = @splat(0), // 8x8-bit registers or 4x16-bit registers
pc: u16 = 0, // 16-bit program counter
sp: u16 = 0, // 16-bit stack pointer

pub const NOP = instructions.NOP;
pub const LD_r16_imm16 = instructions.LD_r16_imm16;
pub const LD_r16mem_A = instructions.LD_r16mem_A;

test "NOP" {
    var gb = Gb{};
    gb.NOP();
    try std.testing.expect(gb.pc == 1);
}

test "LD_r16_imm16" {
    var gb = Gb{};
    gb.RAM[0] = 0b00000001; // Opcode for LD BC, imm16
    gb.RAM[1] = 0x34; // Low byte
    gb.RAM[2] = 0x12; // High byte
    gb.LD_r16_imm16();
    try std.testing.expect(gb.registers[0] == 0x34); // Low byte
    try std.testing.expect(gb.registers[1] == 0x12); // High byte
    try std.testing.expect(gb.pc == 3);

    gb.RAM[3] = 0b00110010; // Opcode for LD SP, imm16
    gb.RAM[4] = 0x78; // Low byte
    gb.RAM[5] = 0x56; // High byte
    gb.LD_r16_imm16();
    try std.testing.expect(gb.sp == 0x7856);
    try std.testing.expect(gb.pc == 6);
}

test "LD_r16mem_A" {
    var gb = Gb{};
    gb.registers[7] = 0xAB; // A register
    gb.RAM[0] = 0b00000010; // Opcode for LD (BC), A
    gb.registers[0] = 0x34; // B register (high byte of BC)
    gb.registers[1] = 0x12; // C register (low byte of BC)
    gb.LD_r16mem_A();
    try std.testing.expect(gb.RAM[0x3412] == 0xAB);
    try std.testing.expect(gb.pc == 1);

    gb.RAM[1] = 0b00100100; // Opcode for LD (HLI), A
    gb.registers[4] = 0x56; // H register (high byte of HL)
    gb.registers[5] = 0xFF; // L register (low byte of HL)
    gb.LD_r16mem_A();
    try std.testing.expect(gb.RAM[0x56FF] == 0xAB);
    try std.testing.expect(gb.registers[4] == 0x57);
    try std.testing.expect(gb.registers[5] == 0x00);
    try std.testing.expect(gb.pc == 2);

    gb.RAM[2] = 0b00110110; // Opcode for LD (HLD), A
    gb.registers[4] = 0x4A; // H register (high byte of HL)
    gb.registers[5] = 0xBC; // L register (low byte of HL)
    gb.LD_r16mem_A();
    try std.testing.expect(gb.RAM[0x4ABC] == 0xAB);
    try std.testing.expect(gb.registers[4] == 0x4A);
    try std.testing.expect(gb.registers[5] == 0xBB);
    try std.testing.expect(gb.pc == 3);
}
