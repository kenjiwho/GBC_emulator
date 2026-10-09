//! DMA controller
const Dma = @This();

const Bus = @import("Bus.zig");
const Ppu = @import("ppu/Ppu.zig");

const DmaMode = enum {
    off,
    oam,
    hblank,
    general,
};

bus: *Bus = undefined,
ppu: *Ppu = undefined,
mode: DmaMode = .off,
// OAM DMA transfer state
T_cycles: usize = 0, // number of T-cycles since the last DMA transfer step
counter: u8 = 0,
oam_source: u16 = 0,

// HDMA transfer state
length: u8 = 0,
hdma_source: u16 = 0,
hdma_destination: u16 = 0,
hdma: [5]u8 = @splat(0), // HDMA1-5 registers

pub fn init(bus: *Bus, ppu: *Ppu) Dma {
    return Dma{ .bus = bus, .ppu = ppu };
}

/// start a DMA transfer from the specified source high byte
pub fn start_oam_dma_transfer(self: *Dma, source_high: u8) void {
    self.oam_source = @as(u16, source_high) << 8;
    self.counter = 160;
    self.mode = .oam;
}

/// perform one byte of the DMA transfer
pub fn step(self: *Dma, T_cycles: usize) void {
    self.T_cycles += T_cycles;

    // DMA transfers 1 byte per M-cycle = 4 T-cycles
    while (self.T_cycles >= 4 and self.mode == .oam) {
        const offset: u16 = 160 - self.counter;

        const value = self.bus.read_raw(self.oam_source + offset);
        self.ppu.write_oam(0xFE00 + offset, value);

        self.counter -= 1;
        if (self.counter == 0) {
            self.mode = .off;
            self.T_cycles = 0;
            break;
        }
        self.T_cycles -= 4;
    }
}

pub fn start_dma_transfer(self: *Dma) void {
    self.length = ((self.hdma[4] & 0b01111111) << 4) - 1;
    self.mode = if ((self.hdma[4] & 0b10000000) == 0) .hblank else .general;
    self.hdma_source = (@as(u16, self.hdma[0]) << 8 | self.hdma[1]) & 0b1111111111110000;
    self.hdma_destination = (@as(u16, self.hdma[2]) << 8 | self.hdma[3]) & 0b0001111111110000;
}

// Memory-mapped I/O read/write
pub fn read(self: *Dma, addr: u16) u8 {
    _ = self;
    _ = addr;
}

pub fn write(self: *Dma, addr: u16, value: u8) void {
    self.hdma[addr - 0xFF51] = value;
    if (addr == 0xFF55) {
        self.start_dma_transfer();
    }
}
