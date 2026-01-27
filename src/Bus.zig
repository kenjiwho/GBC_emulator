//! This module defines the Bus structure that implements Memory-Mapped I/O
//! (MMIO) for a Game Boy Color
const Bus = @This();

const Timer = @import("Timer.zig");
const Mbc = @import("mbc/Mbc.zig").Mbc;
const Io = @import("Io.zig");
const Gbc = @import("Gbc.zig");
const Ppu = @import("ppu/Ppu.zig");
const Dma = @import("Dma.zig");

// Memory Map
ROM: []const u8 = undefined, // 16KiB ROM bank 00 (0000-3FFF) + switchable bank 01-NN (4000-7FFF)
// 8KiB Video RAM switchable 0/1: 8000-9FFF
external_RAM: [0x2000 * 4]u8 = @splat(0), // 8/32KiB External RAM (possibly switchable 00-03): A000-BFFF
WRAM: [0x1000 + (0x1000 * 8)]u8 = @splat(0), // 4KiB Work RAM Bank 0 (C000-CFFF) + 4KiB Work RAM switchable 1-7 (D000-DFFF)
// EchoRAM: Echo of C000-DDFF: E000-FDFF (typically not used)
OAM: [0xA0]u8 = @splat(0), // Object Attribute Memory (OAM): FE00-FE9F
Unusable: [0x60]u8 = @splat(0), // Usage is prohibited: FEA0-FEFF
// I/O Registers: FF00-FF7F
HRAM: [0x7F]u8 = @splat(0), // High RAM: FF80-FFFE
IE: u8 = 0, // Interrupt Enable Register: FFFF

// Modules
timer: Timer,
io: Io,
ppu: *Ppu = undefined,
mbc: Mbc = undefined,
dma: *Dma = undefined,

vbk: u1 = 0, // Current VRAM bank (CGB only)
wbk: u3 = 1, // Current WRAM bank (CGB only)

pub fn init(gb: *Gbc) Bus {
    const timer = Timer.init(&gb.bus);
    const io = Io.init(&gb.bus);

    return Bus{ .timer = timer, .io = io, .ppu = &gb.ppu, .dma = &gb.dma };
}

pub fn insertROM(self: *Bus, rom: []const u8) void {
    self.ROM = rom;

    // setup mbc based on rom header
    const cartridge_type = rom[0x147];
    const rom_size_code = rom[0x148];
    self.mbc = Mbc.init(cartridge_type, rom_size_code);
}

pub fn read(self: *Bus, address: u16) u8 {
    self.timer.tick(); // advance timer on each read

    return switch (address) {
        0x0000...0x3FFF => self.ROM[address],
        0x4000...0x7FFF => self.ROM[self.mbc.mapROMAddress(address)],
        0x8000...0x9FFF => self.ppu.readVram(self.vbk, address),
        0xA000...0xBFFF => if (self.mbc.ExternalRAM_enabled()) self.external_RAM[address - 0xA000] else 0xFF,
        0xC000...0xCFFF => self.WRAM[address - 0xC000],
        0xD000...0xDFFF => self.WRAM[(address - 0xD000) + (@as(u16, self.wbk) * 0x1000)],
        0xE000...0xEFFF => self.WRAM[address - 0xE000], // Echo RAM
        0xF000...0xFDFF => self.WRAM[(address - 0xF000) + (@as(u16, self.wbk) * 0x1000)], // Echo RAM
        0xFE00...0xFE9F => self.OAM[address - 0xFE00],
        0xFEA0...0xFEFF => 0, // Unusable
        0xFF00...0xFF7F => self.io.read(address),
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
        0x8000...0x9FFF => self.ppu.writeVram(self.vbk, address, value),
        0xA000...0xBFFF => {
            if (self.mbc.ExternalRAM_enabled()) {
                self.external_RAM[self.mbc.mapRAMAddress(address)] = value;
            }
        },
        0xC000...0xCFFF => self.WRAM[(address - 0xC000)] = value,
        0xD000...0xDFFF => self.WRAM[(address - 0xD000) + (@as(u16, self.wbk) * 0x1000)] = value,
        0xE000...0xEFFF => self.WRAM[(address - 0xE000)] = value, // Echo RAM
        0xF000...0xFDFF => self.WRAM[(address - 0xF000) + (@as(u16, self.wbk) * 0x1000)] = value, // Echo RAM
        0xFE00...0xFE9F => self.OAM[address - 0xFE00] = value,
        0xFEA0...0xFEFF => {}, // Unusable
        0xFF00...0xFF7F => self.io.write(address, value),
        0xFF80...0xFFFE => self.HRAM[address - 0xFF80] = value,
        0xFFFF => self.IE = value,
    }
}
