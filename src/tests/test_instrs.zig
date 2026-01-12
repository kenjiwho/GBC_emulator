const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../Bus.zig");
const Timer = @import("../Timer.zig");
const Io = @import("../Io.zig");

test "NOP" {
    // setup fake ROM
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    try cpu.step();
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "LD_r16_imm16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b00000001; // Opcode for LD BC, imm16
    rom[1] = 0x34; // Low byte
    rom[2] = 0x12; // High byte
    try cpu.step();
    try std.testing.expectEqual(0x12, cpu.regs.B); // Low byte
    try std.testing.expectEqual(0x34, cpu.regs.C); // High byte
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);

    rom[3] = 0b00110001; // Opcode for LD SP, imm16
    rom[4] = 0x56; // Low byte
    rom[5] = 0x78; // High byte
    try cpu.step();
    try std.testing.expectEqual(0x7856, cpu.regs.SP);
    try std.testing.expectEqual(6, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "LD_r16mem_A" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0xAB; // A register
    rom[0] = 0b00000010; // Opcode for LD (BC), A
    cpu.regs.B = 0xC0; // B register (high byte of BC)
    cpu.regs.C = 0x00; // C register (low byte of BC)
    try cpu.step();
    try std.testing.expectEqual(0xAB, bus.WRAM_0[0]);
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[1] = 0b00100010; // Opcode for LD (DE), A
    cpu.regs.H = 0xC0; // H register (high byte of HL)
    cpu.regs.L = 0xFF; // L register (low byte of HL)
    try cpu.step();
    try std.testing.expectEqual(0xAB, bus.WRAM_0[0x0FF]);
    try std.testing.expectEqual(0xC1, cpu.regs.H);
    try std.testing.expectEqual(0x00, cpu.regs.L);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);

    rom[2] = 0b00110010; // Opcode for LD (HLD), A
    cpu.regs.H = 0xC0; // H register (high byte of HL)
    cpu.regs.L = 0x01; // L register (low byte of HL)
    try cpu.step();
    try std.testing.expectEqual(0xAB, bus.WRAM_0[0]);
    try std.testing.expectEqual(0xC0, cpu.regs.H);
    try std.testing.expectEqual(0x00, cpu.regs.L);
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "LD_A_r16mem" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0x3412] = 0xCD;
    rom[0] = 0b00001010; // Opcode for LD A, (BC)
    cpu.regs.B = 0x34; // B register (high byte of BC)
    cpu.regs.C = 0x12; // C register (low byte of BC)
    try cpu.step();
    try std.testing.expectEqual(0xCD, cpu.regs.A); // A register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "LD_imm16_SP" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.SP = 0x9ABC;
    rom[0] = 0b00001000; // Opcode for LD (imm16), SP
    rom[1] = 0x10; // Low byte of imm16
    rom[2] = 0x80; // High byte of
    try cpu.step();
    try std.testing.expectEqual(0xBC, bus.VRAM[0x0010]); // Low byte of SP
    try std.testing.expectEqual(0x9A, bus.VRAM[0x0011]); // High byte of SP
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(20, timer.counter);
}

test "INC_r16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0xFF; // B register
    cpu.regs.C = 0xFF; // C register
    rom[0] = 0b00000011; // Opcode for INC BC
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.B); // B register
    try std.testing.expectEqual(0x00, cpu.regs.C); // C register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.SP = 0x1234; // SP
    rom[1] = 0b00110011; // Opcode for INC SP
    try cpu.step();
    try std.testing.expectEqual(0x1235, cpu.regs.SP); // SP
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "DEC_r16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0x00; // B register
    cpu.regs.C = 0x00; // C register
    rom[0] = 0b00001011; // Opcode for DEC BC
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.B); // B register
    try std.testing.expectEqual(0xFF, cpu.regs.C); // C register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.SP = 0x0000; // SP
    rom[1] = 0b00111011; // Opcode for DEC SP
    try cpu.step();
    try std.testing.expectEqual(0xFFFF, cpu.regs.SP); // SP
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "ADD_HL_r16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.H = 0x1F; // H register
    cpu.regs.L = 0x34; // L register
    cpu.regs.B = 0x01; // B register
    cpu.regs.C = 0x10; // C register
    rom[0] = 0b00001001; // Opcode for ADD HL, BC
    try cpu.step();
    try std.testing.expectEqual(0x20, cpu.regs.H);
    try std.testing.expectEqual(0x44, cpu.regs.L);
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.F = 0b10100000;
    cpu.regs.H = 0xFF; // H register
    cpu.regs.L = 0xFF; // L register
    cpu.regs.D = 0x00; // D register
    cpu.regs.E = 0x01; // E register
    rom[1] = 0b00011001; // Opcode for ADD HL, DE
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.H);
    try std.testing.expectEqual(0x00, cpu.regs.L);
    try std.testing.expectEqual(0b10110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "INC_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0xFF; // A register
    rom[0] = 0b00111100; // Opcode for INC A
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.A); // A register
    try std.testing.expectEqual(0b10100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "DEC_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x00; // A register
    rom[0] = 0b00111101; // Opcode for DEC A
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "LD_r8_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b00000110; // Opcode for LD B, imm8
    rom[1] = 0x7A; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x7A, cpu.regs.B); // B register
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "RLCA" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b10000001; // A register
    rom[0] = 0b00000111; // Opcode for RLCA
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "RRCA" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b00000011; // A register
    rom[0] = 0b00001111; // Opcode for RRCA
    try cpu.step();
    try std.testing.expectEqual(0b10000001, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "RLA" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b10000001; // A register
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b00010111; // Opcode for RLA
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "RRA" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b00000011; // A register
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b00011111; // Opcode for RRA
    try cpu.step();
    try std.testing.expectEqual(0b10000001, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "DAA" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x98; // A register
    cpu.regs.F = 0b01110000; // Clear all flags
    rom[0] = 0b00100111; // Opcode for DAA
    try cpu.step();
    try std.testing.expectEqual(0x98 - 0x66, cpu.regs.A);
    try std.testing.expectEqual(0b01010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    cpu.regs.A = 0x12; // A register
    cpu.regs.F = 0b00110000; // Set N flag
    rom[1] = 0b00100111; // Opcode for DAA
    try cpu.step();
    try std.testing.expectEqual(0x12 + 0x66, cpu.regs.A);
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "CPL" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b10101010; // A register
    rom[0] = 0b00101111; // Opcode for CPL
    try cpu.step();
    try std.testing.expectEqual(0b01010101, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "SCF" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.F = 0b00000000; // Clear all flags
    rom[0] = 0b00110111; // Opcode for SCF
    try cpu.step();
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "CCF" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b00111111; // Opcode for CCF
    try cpu.step();
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    rom[1] = 0b00111111; // Opcode for CCF
    try cpu.step();
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "JR_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b00011000; // Opcode for JR imm8
    rom[1] = 0x05; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x07, cpu.regs.PC); // PC should be 0 + 2 + 5
    try std.testing.expectEqual(12, timer.counter);

    rom[8] = @bitCast(@as(i8, -2)); // imm8 value to jump back
    rom[7] = 0b00011000; // Opcode for JR imm8
    try cpu.step();
    try std.testing.expectEqual(0x07, cpu.regs.PC); // PC should be 7 + 2 - 2
}

test "JR_cond_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b00100000; // Opcode for JR NZ, imm8
    rom[1] = 0x04; // imm8 value
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x06, cpu.regs.PC); // PC should be 0 + 2 + 4
    try std.testing.expectEqual(12, timer.counter);

    rom[6] = 0b00100000; // Opcode for JR NZ, imm8
    rom[7] = 0x04; // imm8 value
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x08, cpu.regs.PC); // PC should be 6 + 2
    try std.testing.expectEqual(20, timer.counter);
}

// test "STOP" {
// var rom: [0x8000]u8 = @splat(0);
//     var bus = Bus.init();
// var cpu = CPU.init(&bus);
// var timer = Timer.init(&bus);
// var io = Io.init(&bus);
// bus.timer = &timer;
// bus.io = &io;
//     bus.ROM = rom[0..];
//     bus.write(0, 0b00010000); // Opcode for HALT
//     try cpu.execute();
//     try std.testing.expectEqual(1, cpu.regs.PC);
// }

test "LD_r8_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0x56;
    rom[0] = 0b01000000; // Opcode for LD B, B
    try cpu.step();
    try std.testing.expectEqual(0x56, cpu.regs.B); // B register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    cpu.regs.C = 0x78;
    rom[1] = 0b01000001; // Opcode for LD B, C
    try cpu.step();
    try std.testing.expectEqual(0x78, cpu.regs.B); // B register
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.D = 0x9A;
    rom[2] = 0b01110010; // Opcode for LD [HL], D
    cpu.regs.H = 0xC0;
    cpu.regs.L = 0x00;
    try cpu.step();
    try std.testing.expectEqual(0x9A, bus.WRAM_0[0]); // Memory at HL
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "HALT" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b01110110; // Opcode for HALT
    try cpu.step();
    try std.testing.expectEqual(true, cpu.halted);
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "ADD_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x14;
    cpu.regs.B = 0x28;
    rom[0] = 0b10000000; // Opcode for ADD A, B
    try cpu.step();
    try std.testing.expectEqual(0x3C, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    rom[1] = 0b10000110; // Opcode for ADD [HL], B
    cpu.regs.H = 0x00;
    cpu.regs.L = 0x10;
    rom[0x0010] = 0x28;
    try cpu.step();
    try std.testing.expectEqual(0x64, cpu.regs.A);
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);
}

test "ADC_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x14;
    cpu.regs.B = 0x28;
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b10001000; // Opcode for ADC A, B
    try cpu.step();
    try std.testing.expectEqual(0x3D, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    rom[1] = 0b10001000; // Opcode for ADC A, B
    cpu.regs.B = 0xC2;
    cpu.regs.F = 0b00110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.A);
    try std.testing.expectEqual(0b10110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "SUB_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x50;
    cpu.regs.B = 0x20;
    rom[0] = 0b10010000; // Opcode for SUB A, B
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A);
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    rom[1] = 0b10010000; // Opcode for SUB A, B
    cpu.regs.B = 0x01;
    try cpu.step();
    try std.testing.expectEqual(0x2F, cpu.regs.A);
    try std.testing.expectEqual(0b01100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "SBC_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x50;
    cpu.regs.B = 0x20;
    rom[0] = 0b10011000; // Opcode for SBC A, B
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    rom[1] = 0b10011000; // Opcode for SBC A, B
    cpu.regs.B = 0x30;
    cpu.regs.F = 0b01110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "AND_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b11001100;
    cpu.regs.B = 0b10101010;
    rom[0] = 0b10100000; // Opcode for AND A, B
    try cpu.step();
    try std.testing.expectEqual(0b10001000, cpu.regs.A);
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "XOR_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b11001100;
    cpu.regs.B = 0b10101010;
    rom[0] = 0b10101000; // Opcode for XOR A, B
    try cpu.step();
    try std.testing.expectEqual(0b01100110, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "OR_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b11001100;
    cpu.regs.B = 0b10101010;
    rom[0] = 0b10110000; // Opcode for OR A, B
    try cpu.step();
    try std.testing.expectEqual(0b11101110, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "CP_A_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x50;
    cpu.regs.B = 0x20;
    rom[0] = 0b10111000; // Opcode for CP A, B
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    rom[1] = 0b10111000; // Opcode for CP A, B
    cpu.regs.B = 0x60;
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "ADD_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x10;
    rom[0] = 0b11000110; // Opcode for ADD A, imm8
    rom[1] = 0x22; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x32, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[2] = 0b11000110; // Opcode for ADD A, imm8
    rom[3] = 0xD0; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x02, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "ADC_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x10;
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b11001110; // Opcode for ADC A, imm8
    rom[1] = 0x22; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x33, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[2] = 0b11001110; // Opcode for ADC A, imm8
    rom[3] = 0xD0; // imm8 value
    cpu.regs.F = 0b00110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0x04, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "SUB_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x50;
    rom[0] = 0b11010110; // Opcode for SUB A, imm8
    rom[1] = 0x20; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[2] = 0b11010110; // Opcode for SUB A, imm8
    rom[3] = 0x31; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "SBC_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x50;
    rom[0] = 0b11011110; // Opcode for SBC A, imm8
    rom[1] = 0x20; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[2] = 0b11011110; // Opcode for SBC A, imm8
    rom[3] = 0x31; // imm8 value
    cpu.regs.F = 0b01110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0xFE, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "AND_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b11001100;
    rom[0] = 0b11100110; // Opcode for AND A, imm8
    rom[1] = 0b10101010; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0b10001000, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "XOR_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b11001100;
    rom[0] = 0b11101110; // Opcode for XOR A, imm8
    rom[1] = 0b10101010; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0b01100110, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "OR_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0b11001100;
    rom[0] = 0b11110110; // Opcode for OR A, imm8
    rom[1] = 0b10101010; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0b11101110, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "CP_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x50;
    rom[0] = 0b11111110; // Opcode for CP A, imm8
    rom[1] = 0x20; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[2] = 0b11111110; // Opcode for CP A, imm8
    rom[3] = 0x60; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "RET" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xDFFE;
    rom[0] = 0b11001001; // Opcode for RET
    bus.WRAM_S[0x0FFE] = 0x34; // Low byte of return address
    bus.WRAM_S[0x0FFF] = 0x12; // High byte of return address
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to return address
    try std.testing.expectEqual(0xE000, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(16, timer.counter);
}

test "RET_cond" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xFFFD;
    rom[0] = 0b11000000; // Opcode for RET NZ
    bus.HRAM[0xFFFD - 0xFF80] = 0x34; // Low byte of return address
    bus.HRAM[0xFFFE - 0xFF80] = 0x12; // High byte of return address
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to return address
    try std.testing.expectEqual(0xFFFF, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(20, timer.counter);

    // Prepare stack again
    cpu.regs.SP = 0xFFFD;
    bus.HRAM[0xFFFD - 0xFF80] = 0x78; // Low byte of return address
    bus.HRAM[0xFFFE - 0xFF80] = 0x56; // High byte of return address
    rom[0x1234] = 0b11000000; // Opcode for RET NZ
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x1235, cpu.regs.PC); // PC should just increment
    try std.testing.expectEqual(0xFFFD, cpu.regs.SP); // SP should remain unchanged
    try std.testing.expectEqual(28, timer.counter);
}

test "RETI" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xFFFC;
    bus.HRAM[0xFFFC - 0xFF80] = 0x34; // Low byte of return address
    bus.HRAM[0xFFFD - 0xFF80] = 0x12; // High byte of return address
    rom[0] = 0b11011001; // Opcode for RETI
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to return address
    try std.testing.expectEqual(0xFFFE, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(true, cpu.IME); // Interrupts should be enabled
    try std.testing.expectEqual(16, timer.counter);
}

test "JP_imm16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b11000011; // Opcode for JP imm16
    rom[1] = 0x12; // Low byte of address
    rom[2] = 0x34; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(16, timer.counter);
}

test "JP_cond_imm16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b11000010; // Opcode for JP NZ, imm16
    rom[1] = 0x12; // Low byte of address
    rom[2] = 0x34; // High byte of address
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(16, timer.counter);

    rom[0x3412] = 0b11000010; // Opcode for JP NZ, imm16
    rom[0x3413] = 0x56; // Low byte of address
    rom[0x3414] = 0x78; // High byte of address
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x3415, cpu.regs.PC); // PC should just increment
    try std.testing.expectEqual(28, timer.counter);
}

test "JP_HL" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.H = 0x12; // H register
    cpu.regs.L = 0x34; // L register
    rom[0] = 0b11101001; // Opcode for JP HL
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to HL value
    try std.testing.expectEqual(4, timer.counter);
}

test "CALL_imm16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xFFFE;

    rom[0] = 0b11001101; // Opcode for CALL imm16
    rom[1] = 0x12; // Low byte of address
    rom[2] = 0x34; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x03, bus.HRAM[0xFFFC - 0xFF80]); // Low byte of return address
    try std.testing.expectEqual(0x00, bus.HRAM[0xFFFD - 0xFF80]); // High byte of return address
    try std.testing.expectEqual(24, timer.counter);
}

test "CALL_cond_imm16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xFFFE;
    rom[0] = 0b11000100; // Opcode for CALL NZ, imm16
    rom[1] = 0x12; // Low byte of address
    rom[2] = 0x34; // High byte of address
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x03, bus.HRAM[0xFFFC - 0xFF80]); // Low byte of return address
    try std.testing.expectEqual(0x00, bus.HRAM[0xFFFD - 0xFF80]); // High byte of return address
    try std.testing.expectEqual(24, timer.counter);

    // Prepare stack again
    cpu.regs.SP = 0xFFFE;
    rom[0x3412] = 0b11000100; // Opcode for CALL NZ, imm16
    rom[0x3413] = 0x56; // Low byte of address
    rom[0x3414] = 0x78; // High byte of address
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x3415, cpu.regs.PC); // PC should just increment
    try std.testing.expectEqual(0xFFFE, cpu.regs.SP); // SP should remain unchanged
    try std.testing.expectEqual(36, timer.counter);
}

test "RST_tgt3" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xFFFE;
    rom[0] = 0b11011111; // Opcode for RST $18
    try cpu.step();
    try std.testing.expectEqual(0x18, cpu.regs.PC); // PC should be set to target address
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x01, bus.HRAM[0xFFFC - 0xFF80]); // Low byte of return address
    try std.testing.expectEqual(0x00, bus.HRAM[0xFFFD - 0xFF80]); // High byte of return address
    try std.testing.expectEqual(16, timer.counter);
}

test "POP_r16stk" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    // Prepare stack
    cpu.regs.SP = 0xFFFC;
    bus.HRAM[0xFFFC - 0xFF80] = 0x34; // Low byte
    bus.HRAM[0xFFFD - 0xFF80] = 0x12; // High byte
    rom[0] = 0b11000001; // Opcode for POP BC
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.getR16(0)); // BC register
    try std.testing.expectEqual(0xFFFE, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(12, timer.counter);
}

test "PUSH_r16stk" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.setR16(0, 0x1234); // BC register
    cpu.regs.SP = 0xFFFE;
    rom[0] = 0b11000101; // Opcode for PUSH BC
    try cpu.step();
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x12, bus.HRAM[0xFFFD - 0xFF80]); // High byte
    try std.testing.expectEqual(0x34, bus.HRAM[0xFFFC - 0xFF80]); // Low byte
    try std.testing.expectEqual(16, timer.counter);
}

test "LDH_C_A" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.C = 0x80; // C register
    cpu.regs.A = 0x42; // A register
    rom[0] = 0b11100010; // Opcode for LDH (C), A
    try cpu.step();
    try std.testing.expectEqual(0x42, bus.HRAM[0]); // Check memory
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "LDH_imm8_A" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x37; // A register
    rom[0] = 0b11100000; // Opcode for LD (imm8), A
    rom[1] = 0x80; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x37, bus.HRAM[0]); // Check memory
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);
}

test "LD_imm16_A" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.A = 0x55; // A register
    rom[0] = 0b11101010; // Opcode for LD (imm16), A
    rom[1] = 0x00; // Low byte of address
    rom[2] = 0xC0; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x55, bus.WRAM_0[0]); // Check memory
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "LDH_A_C" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    bus.HRAM[0] = 0x7A; // Memory at address FF20
    cpu.regs.C = 0x80; // C register
    rom[0] = 0b11110010; // Opcode for LDH A, (C)
    try cpu.step();
    try std.testing.expectEqual(0x7A, cpu.regs.A); // A register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "LDH_A_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    bus.HRAM[0] = 0x8B; // Memory at address FF30
    rom[0] = 0b11110000; // Opcode for LDH A, (imm8)
    rom[1] = 0x80; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x8B, cpu.regs.A); // A register
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);
}

test "LD_A_imm16" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0x00C1] = 0x9C; // Memory at address C100
    rom[0] = 0b11111010; // Opcode for LD A, (imm16)
    rom[1] = 0xC1; // Low byte of address
    rom[2] = 0x00; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x9C, cpu.regs.A); // A register
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "ADD_SP_imm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.SP = 0xFFF8;
    rom[0] = 0b11101000; // Opcode for ADD SP, imm8
    rom[1] = 0x08; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x0000, cpu.regs.SP); // SP should wrap around
    try std.testing.expectEqual(0b00110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);

    cpu.regs.SP = 0x0004;
    rom[2] = 0b11101000; // Opcode for ADD SP, imm8
    rom[3] = @bitCast(@as(i8, -5)); // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0xFFFF, cpu.regs.SP); // SP should be 4 - 6 = FFFF (wrap around)
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
}

test "LD_HL_SPimm8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.SP = 0xFFF8;
    rom[0] = 0b11111000; // Opcode for LD HL, SP+imm8
    rom[1] = 0x08; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0xFFF8, cpu.regs.SP); // SP should stay the same
    try std.testing.expectEqual(0x0000, cpu.regs.getHL()); // HL should be SP + 8 = 0x0000 (wrap around)
    try std.testing.expectEqual(0b00110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);

    cpu.regs.SP = 0x0004;
    rom[2] = 0b11111000; // Opcode for LD HL, SP+imm8
    rom[3] = @bitCast(@as(i8, -5)); // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x0004, cpu.regs.SP); // SP should stay the same
    try std.testing.expectEqual(0xFFFF, cpu.regs.getHL()); // HL should be SP - 6 = FFFF (wrap around)
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "LD_SP_HL" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.H = 0x12; // H register
    cpu.regs.L = 0x34; // L register
    rom[0] = 0b11111001; // Opcode for LD SP, HL
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.SP); // SP should be set to HL value
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "EI" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0b11111011; // Opcode for EI
    try cpu.step();
    try std.testing.expectEqual(true, cpu.IME_scheduled); // Interrupts scheduled to be enabled
    try std.testing.expectEqual(false, cpu.IME); // But not yet enabled
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    try cpu.step(); // Next instruction
    try std.testing.expectEqual(false, cpu.IME_scheduled); // Interrupts no longer scheduled
    try std.testing.expectEqual(true, cpu.IME); // IME set
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "DI" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.IME = true;
    rom[0] = 0b11110011; // Opcode for DI
    try cpu.step();
    try std.testing.expectEqual(false, cpu.IME); // Interrupts should be disabled
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "OpcodeHole" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    rom[0] = 0xD3; // Invalid Opcode
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[1] = 0xDB;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[2] = 0xDD;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[3] = 0xE3;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[4] = 0xE4;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[5] = 0xEB;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[6] = 0xEC;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[7] = 0xED;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[8] = 0xF4;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[9] = 0xFC;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    rom[10] = 0xFD;
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
}

// ------------------------ CB prefix tests ----------------------
test "RLC_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00000000; // Opcode for RLC B
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // set HL
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00000110; // Opcode for RLC (HL)
    try cpu.step();
    try std.testing.expectEqual(0b10000001, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "RRC_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00001000; // Opcode for RRC B
    try cpu.step();
    try std.testing.expectEqual(0b11000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00001110; // Opcode for RRC (HL)
    try cpu.step();
    try std.testing.expectEqual(0b01100000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "RL_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00010000; // Opcode for RL B
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // (HL)
    cpu.regs.F = 0b00000000; // Clear Carry flag
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00010110; // Opcode for RL (HL)
    try cpu.step();
    try std.testing.expectEqual(0b10000000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "RR_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    cpu.regs.F = 0b00010000; // Set Carry flag
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00011000; // Opcode for RR B
    try cpu.step();
    try std.testing.expectEqual(0b11000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // (HL)
    cpu.regs.F = 0b00000000; // Clear Carry flag
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00011110; // Opcode for RR (HL)
    try cpu.step();
    try std.testing.expectEqual(0b01100000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SLA_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00100000; // Opcode for SLA B
    try cpu.step();
    try std.testing.expectEqual(0b00000010, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00100110; // Opcode for SLA (HL)
    try cpu.step();
    try std.testing.expectEqual(0b10000000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SRA_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00101000; // Opcode for SRA B
    try cpu.step();
    try std.testing.expectEqual(0b11000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00101110; // Opcode for SRA (HL)
    try cpu.step();
    try std.testing.expectEqual(0b11100000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SWAP_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10110001; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00110000; // Opcode for SWAP B
    try cpu.step();
    try std.testing.expectEqual(0b00011011, cpu.regs.B);
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b10110001; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00110110; // Opcode for SWAP (HL)
    try cpu.step();
    try std.testing.expectEqual(0b00011011, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SRL_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b10000001; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b00111000; // Opcode for SRL B
    try cpu.step();
    try std.testing.expectEqual(0b01000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11000000; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b00111110; // Opcode for SRL (HL)
    try cpu.step();
    try std.testing.expectEqual(0b01100000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "BIT_b3_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b00001000; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b01000000; // Opcode for BIT 0, B
    try cpu.step();
    try std.testing.expectEqual(0b10100000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    rom[0] = 0b00001000; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b01011110; // Opcode for BIT 3, (HL)
    try cpu.step();
    try std.testing.expectEqual(0b00001000, rom[0]); // (HL)
    try std.testing.expectEqual(0b00100000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(20, timer.counter);
}

test "RES_b3_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b11111111; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b10000000; // Opcode for RES 0, B
    try cpu.step();
    try std.testing.expectEqual(0b11111110, cpu.regs.B);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b11111111; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b10011110; // Opcode for RES 3, (HL)
    try cpu.step();
    try std.testing.expectEqual(0b11110111, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SET_b3_r8" {
    var rom: [0x8000]u8 = @splat(0);
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    var io = Io.init(&bus);
    bus.timer = &timer;
    bus.io = &io;
    bus.ROM = rom[0..];
    cpu.regs.B = 0b00000000; // B register
    rom[0] = 0b11001011; // CB Prefix
    rom[1] = 0b11000000; // Opcode for SET 0, B
    try cpu.step();
    try std.testing.expectEqual(0b00000001, cpu.regs.B);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.setHL(0xC000);
    bus.WRAM_0[0] = 0b00000000; // (HL)
    rom[2] = 0b11001011; // CB Prefix
    rom[3] = 0b11011110; // Opcode for SET 3, (HL)
    try cpu.step();
    try std.testing.expectEqual(0b00001000 | 0b00001000, bus.WRAM_0[0]); // (HL)
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}
