//! DMA controller
const Dma = @This();

const Bus = @import("Bus.zig");

bus: *Bus = undefined,
counter: u8 = 0,
source: u16 = 0,

pub fn init(bus: *Bus) Dma {
    return Dma{ .bus = bus };
}

/// start a DMA transfer from the specified source high byte
pub fn startTransfer(self: *Dma, source_high: u8) void {
    self.source = @as(u16, source_high) << 8;
    self.counter = 160;
}

/// perform one byte of the DMA transfer
pub fn step(self: *Dma) void {
    const offset = 160 - self.counter;

    const value = self.bus.read(self.source + offset);
    self.bus.OAM[offset] = value;

    self.counter -= 1;
}
