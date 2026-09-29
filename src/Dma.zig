//! DMA controller
const Dma = @This();

const Bus = @import("Bus.zig");
const Ppu = @import("ppu/Ppu.zig");

bus: *Bus = undefined,
ppu: *Ppu = undefined,
counter: u8 = 0,
source: u16 = 0,

pub fn init(bus: *Bus, ppu: *Ppu) Dma {
    return Dma{ .bus = bus, .ppu = ppu };
}

/// start a DMA transfer from the specified source high byte
pub fn startTransfer(self: *Dma, source_high: u8) void {
    self.source = @as(u16, source_high) << 8;
    self.counter = 160;
}

/// perform one byte of the DMA transfer
pub fn step(self: *Dma) void {
    const offset: u16 = 160 - self.counter;

    const value = self.bus.read(self.source + offset);
    self.ppu.write_oam(0xFE00 + offset, value);

    self.counter -= 1;
}
