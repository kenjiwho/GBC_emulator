//! This module defines the Memory-Mapped I/O (MMIO) structure for a Game Boy Color
const MMIO = @This();

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

pub fn init() MMIO {
    return MMIO{};
}

pub fn read(self: *const MMIO, address: u16) u8 {
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
        0xFF00...0xFF7F => self.IOPorts[address - 0xFF00],
        0xFF80...0xFFFE => self.HRAM[address - 0xFF80],
        0xFFFF => self.IE,
    };
}

pub fn write(self: *MMIO, address: u16, value: u8) void {
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
        0xFF00...0xFF7F => self.IOPorts[address - 0xFF00] = value,
        0xFF80...0xFFFE => self.HRAM[address - 0xFF80] = value,
        0xFFFF => self.IE = value,
    }
}
