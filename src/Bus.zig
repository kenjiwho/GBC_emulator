//! This module defines the Bus structure that implements Memory-Mapped I/O
//! (MMIO) for a Game Boy Color
const Bus = @This();

const Timer = @import("Timer.zig");

// Memory Map
ROM_0: [0x4000]u8 = @splat(0), // 16KiB ROM Bank 00: 0000-3FFF
ROM_S: [0x4000]u8 = @splat(0), // 16KiB Switchable ROM Bank 01-NN: 4000-7FFF
VRAM: [0x2000]u8 = @splat(0), // 8KiB Video RAM (GBC mode: switchable 0/1): 8000-9FFF
ExternalRAM: [0x2000]u8 = @splat(0), // 8KiB External RAM (possibly switchable): A000-BFFF
WRAM_0: [0x1000]u8 = @splat(0), // 4KiB Work RAM Bank 0: C000-CFFF
WRAM_S: [0x1000]u8 = @splat(0), // 4KiB Work RAM (GBC mode: switchable 1-7): D000-DFFF
// EchoRAM: Echo of C000-DDFF: E000-FDFF (typically not used)
OAM: [0xA0]u8 = @splat(0), // Object Attribute Memory (OAM): FE00-FE9F
Unusable: [0x60]u8 = @splat(0), // Usage is prohibited: FEA0-FEFF
IOPorts: [0x80]u8 = @splat(0), // I/O Registers: FF00-FF7F
HRAM: [0x7F]u8 = @splat(0), // High RAM: FF80-FFFE
IE: u8 = 0, // Interrupt Enable Register: FFFF

// Modules
timer: *Timer = undefined,

const interrupts = enum(u3) {
    VBlank = 0,
    LCD = 1,
    Timer = 2,
    Serial = 3,
    Joypad = 4,
};

pub fn init() Bus {
    return Bus{};
}

pub fn read(self: *const Bus, address: u16) u8 {
    self.timer.tick(); // advance timer on each read

    return switch (address) {
        0x0000...0x3FFF => self.ROM_0[address],
        0x4000...0x7FFF => self.ROM_S[address - 0x4000],
        0x8000...0x9FFF => self.VRAM[address - 0x8000],
        0xA000...0xBFFF => self.ExternalRAM[address - 0xA000],
        0xC000...0xCFFF => self.WRAM_0[address - 0xC000],
        0xD000...0xDFFF => self.WRAM_S[address - 0xD000],
        0xE000...0xEFFF => self.WRAM_0[address - 0xE000], // Echo RAM
        0xF000...0xFDFF => self.WRAM_S[address - 0xF000], // Echo RAM
        0xFE00...0xFE9F => self.OAM[address - 0xFE00],
        0xFEA0...0xFEFF => 0, // Unusable
        0xFF00...0xFF7F => self.handleIORead(address),
        0xFF80...0xFFFE => self.HRAM[address - 0xFF80],
        0xFFFF => self.IE,
    };
}

// --------------------- USED IN BLARGG TESTING ---------------------
pub fn read_no_tick(self: *const Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x3FFF => self.ROM_0[address],
        0x4000...0x7FFF => self.ROM_S[address - 0x4000],
        0x8000...0x9FFF => self.VRAM[address - 0x8000],
        0xA000...0xBFFF => self.ExternalRAM[address - 0xA000],
        0xC000...0xCFFF => self.WRAM_0[address - 0xC000],
        0xD000...0xDFFF => self.WRAM_S[address - 0xD000],
        0xE000...0xEFFF => self.WRAM_0[address - 0xE000], // Echo RAM
        0xF000...0xFDFF => self.WRAM_S[address - 0xF000], // Echo RAM
        0xFE00...0xFE9F => self.OAM[address - 0xFE00],
        0xFEA0...0xFEFF => 0, // Unusable
        0xFF00...0xFF7F => self.handleIORead(address),
        0xFF80...0xFFFE => self.HRAM[address - 0xFF80],
        0xFFFF => self.IE,
    };
}
// ----------------------------------------------------------------------

pub fn write(self: *Bus, address: u16, value: u8) void {
    self.timer.tick(); // advance timer on each write

    switch (address) {
        0x0000...0x3FFF => self.ROM_0[address] = value,
        0x4000...0x7FFF => self.ROM_S[address - 0x4000] = value,
        0x8000...0x9FFF => self.VRAM[address - 0x8000] = value,
        0xA000...0xBFFF => self.ExternalRAM[address - 0xA000] = value,
        0xC000...0xCFFF => self.WRAM_0[address - 0xC000] = value,
        0xD000...0xDFFF => self.WRAM_S[address - 0xD000] = value,
        0xE000...0xEFFF => self.WRAM_0[address - 0xE000] = value, // Echo RAM
        0xF000...0xFDFF => self.WRAM_S[address - 0xF000] = value, // Echo RAM
        0xFE00...0xFE9F => self.OAM[address - 0xFE00] = value,
        0xFEA0...0xFEFF => {}, // Unusable
        0xFF00...0xFF7F => self.handleIOWrite(address, value),
        0xFF80...0xFFFE => self.HRAM[address - 0xFF80] = value,
        0xFFFF => self.IE = value,
    }
}

/// Seperate getters and setters for IF and IE when they should not tick the timer
pub fn getIF(self: *const Bus) u8 {
    return self.IOPorts[0x0F];
}

pub fn getIE(self: *const Bus) u8 {
    return self.IE;
}

pub fn setIF(self: *Bus, value: u8) void {
    self.IOPorts[0x0F] = value;
}

pub fn setIE(self: *Bus, value: u8) void {
    self.IE = value;
}

pub fn requestInterrupt(self: *Bus, interrupt: interrupts) void {
    const interrupt_flag = self.IOPorts[0x0F];
    const new_flag = interrupt_flag | (@as(u8, 1) << @intFromEnum(interrupt));
    self.IOPorts[0x0F] = new_flag;
}

fn handleIOWrite(self: *Bus, address: u16, value: u8) void {
    // --------------------- USED IN BLARGG TESTING ---------------------
    // Handle blargg test output to serial port
    if (address == 0xFF02 and value == 0x81) {
        const byte = self.read(0xFF01);
        std.debug.print("{c}", .{byte});
    }
    // ----------------------------------------------------------------------

    switch (address) {
        0xFF04...0xFF07 => self.timer.write(address, value),
        else => self.IOPorts[address - 0xFF00] = value,
    }
}

fn handleIORead(self: *const Bus, address: u16) u8 {
    // --------------------- USED IN BLARGG TESTING ---------------------
    // Handle blargg test output to serial port
    if (address == 0xFF44) {
        return 0x90;
    }
    // ----------------------------------------------------------------------

    return switch (address) {
        0xFF04...0xFF07 => self.timer.read(address),
        else => self.IOPorts[address - 0xFF00],
    };
}

const std = @import("std");
