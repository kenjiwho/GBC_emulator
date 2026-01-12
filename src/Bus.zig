//! This module defines the Bus structure that implements Memory-Mapped I/O
//! (MMIO) for a Game Boy Color
const Bus = @This();

const Timer = @import("Timer.zig");
const MBC = @import("MBC.zig").MBC;

// Memory Map
ROM: []const u8 = undefined, // 16KiB ROM bank 00 (0000-3FFF) + switchable bank 01-NN (4000-7FFF)
VRAM: [0x2000]u8 = @splat(0), // 8KiB Video RAM (GBC mode: switchable 0/1): 8000-9FFF
ExternalRAM: [0x8000]u8 = @splat(0), // 8KiB External RAM (possibly switchable 00-03): A000-BFFF
WRAM_0: [0x1000]u8 = @splat(0), // 4KiB Work RAM Bank 0: C000-CFFF
WRAM_S: [0x1000]u8 = @splat(0), // 4KiB Work RAM (GBC mode: switchable 1-7): D000-DFFF
// EchoRAM: Echo of C000-DDFF: E000-FDFF (typically not used)
OAM: [0xA0]u8 = @splat(0), // Object Attribute Memory (OAM): FE00-FE9F
Unusable: [0x60]u8 = @splat(0), // Usage is prohibited: FEA0-FEFF
IOPorts: [0x80]u8 = @splat(0), // I/O Registers: FF00-FF7F
HRAM: [0x7F]u8 = @splat(0), // High RAM: FF80-FFFE
IE: u8 = 0, // Interrupt Enable Register: FFFF

joyp_action: u8 = 0xF,
joyp_direction: u8 = 0xF,

// Modules
timer: *Timer = undefined,
mbc: MBC = undefined,

const interrupts = enum(u3) {
    VBlank = 0,
    LCD = 1,
    Timer = 2,
    Serial = 3,
    Joypad = 4,
};

pub fn init() Bus {
    var bus = Bus{};
    bus.IOPorts[0] = 0xCF; // Initialize JOYP register

    return bus;
}

pub fn insertROM(self: *Bus, rom: []const u8) void {
    self.ROM = rom;

    // setup mbc based on rom header
    const cartridge_type = rom[0x147];
    const rom_size_code = rom[0x148];
    self.mbc = MBC.init(cartridge_type, rom_size_code);
}

pub fn read(self: *const Bus, address: u16) u8 {
    self.timer.tick(); // advance timer on each read

    return switch (address) {
        0x0000...0x3FFF => self.ROM[address],
        0x4000...0x7FFF => self.ROM[self.mbc.mapROMAddress(address)],
        0x8000...0x9FFF => self.VRAM[address - 0x8000],
        0xA000...0xBFFF => if (self.mbc.ExternalRAM_enabled()) self.ExternalRAM[address - 0xA000] else 0xFF,
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

pub fn write(self: *Bus, address: u16, value: u8) void {
    self.timer.tick(); // advance timer on each write

    switch (address) {
        0x0000...0x1FFF => self.mbc.toggleExternalRAM(value),
        0x2000...0x3FFF => self.mbc.setROMBank(value),
        0x4000...0x5FFF => self.mbc.setSecondaryBank(value),
        0x6000...0x7FFF => self.mbc.setMode(value),
        0x8000...0x9FFF => self.VRAM[address - 0x8000] = value,
        0xA000...0xBFFF => {
            if (self.mbc.ExternalRAM_enabled()) {
                self.ExternalRAM[self.mbc.mapRAMAddress(address)] = value;
            }
        },
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

fn handleIORead(self: *const Bus, address: u16) u8 {
    // --------------------- USED IN BLARGG TESTING ---------------------
    // Handle blargg test output to serial port
    if (address == 0xFF44) {
        return 0x90;
    }
    // ----------------------------------------------------------------------

    return switch (address) {
        0xFF00 => self.getJoyp(),
        0xFF04...0xFF07 => self.timer.read(address),
        0xFF4D => self.getKey1(),
        else => self.IOPorts[address - 0xFF00],
    };
}

fn handleIOWrite(self: *Bus, address: u16, value: u8) void {
    // --------------------- USED IN BLARGG TESTING ---------------------
    // Handle blargg test output to serial port
    if (address == 0xFF02 and value == 0x81) {
        const byte = self.IOPorts[0x01];
        std.debug.print("{c}", .{byte});
    }
    // ----------------------------------------------------------------------

    switch (address) {
        0xFF00 => self.setJoyp(value),
        0xFF04...0xFF07 => self.timer.write(address, value),
        0xFF4D => self.setKey1(value),
        else => self.IOPorts[address - 0xFF00] = value,
    }
}

/// Seperate getters and setters when reads/writes should not tick the timer
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

pub fn getJoyp(self: *const Bus) u8 {
    var joyp = self.IOPorts[0x00];
    if ((joyp & 0x10) == 0) {
        joyp &= (self.joyp_direction | 0xF0);
    }
    if ((joyp & 0x20) == 0) {
        joyp &= (self.joyp_action | 0xF0);
    }
    return joyp;
}

fn setJoyp(self: *Bus, value: u8) void {
    self.IOPorts[0x00] = (self.IOPorts[0x00] & 0xCF) | (value & 0x30);
}

pub fn getKey1(self: *const Bus) u8 {
    return self.IOPorts[0x4D];
}

fn setKey1(self: *Bus, value: u8) void {
    self.IOPorts[0x4D] = (self.IOPorts[0x4D] & 0x80) | (value & 0x01);
}

pub fn requestInterrupt(self: *Bus, interrupt: interrupts) void {
    const interrupt_flag = self.IOPorts[0x0F];
    const new_flag = interrupt_flag | (@as(u8, 1) << @intFromEnum(interrupt));
    self.IOPorts[0x0F] = new_flag;
}

pub fn toggleSpeed(self: *Bus) void {
    var key1 = self.getKey1();
    key1 ^= 0x80;
    key1 &= 0x80;
    self.setKey1(key1);
}

const std = @import("std");
