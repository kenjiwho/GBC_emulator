//! DMA controller
const Dma = @This();

const Bus = @import("Bus.zig");
const Ppu = @import("ppu/Ppu.zig");

const Hdma5 = packed struct {
    length: u7 = 0, // 0-6: 16-byte blocks to transfer
    mode: u1 = 0, // 7: 0 = General DMA, 1 = H-Blank DMA
};

bus: *Bus = undefined,
ppu: *Ppu = undefined,
oam_DMA: bool = false, // if true, OAM DMA transfer is in progress
hblank_DMA: bool = false, // if true, H-Blank DMA transfer is in progress

// OAM DMA transfer state
T_cycles: usize = 0, // number of T-cycles since the last DMA transfer step
counter: u8 = 0,
oam_source: u16 = 0,

// HDMA transfer state
hdma1: u8 = 0, // HDMA1 - Source high byte
hdma2: u8 = 0, // HDMA2 - Source low byte
hdma3: u8 = 0, // HDMA3 - Destination high byte
hdma4: u8 = 0, // HDMA4 - Destination low byte
hdma5: Hdma5 = .{}, // HDMA5 - Length/Mode/Start

pub fn init(bus: *Bus, ppu: *Ppu) Dma {
    return Dma{ .bus = bus, .ppu = ppu };
}

/// start a DMA transfer from the specified source high byte
pub fn start_oam_dma_transfer(self: *Dma, source_high: u8) void {
    std.log.info("oam DMA", .{});
    self.oam_source = @as(u16, source_high) << 8;
    self.counter = 160;
    self.oam_DMA = true;
}

pub fn start_dma_transfer(self: *Dma) void {
    if ((self.hdma5.mode) == 1) {
        std.log.info("hblank DMA", .{});
        self.hblank_DMA = true;
    } else {
        if (self.hblank_DMA) {
            // if a H-Blank DMA transfer is in progress, the general dma request is a cancel command
            self.hblank_DMA = false;
            return;
        }
        self.perform_general_DMA();
    }
}

/// perform one byte of the oam DMA transfer
pub fn step_oam(self: *Dma, T_cycles: usize) void {
    self.T_cycles += T_cycles;

    // DMA transfers 1 byte per 1 M-cycle = 4 T-cycles
    while (self.T_cycles >= 4 and self.oam_DMA) {
        const offset: u16 = 160 - self.counter;

        const value = self.bus.read_raw(self.oam_source + offset);
        self.ppu.write_oam(0xFE00 + offset, value);

        self.counter -= 1;
        if (self.counter == 0) {
            self.oam_DMA = false;
            self.T_cycles = 0;
            break;
        }
        self.T_cycles -= 4;
    }
}

/// perform one step of one step of hblank DMA trasnfer
pub fn step_hblank(self: *Dma) void {
    var source = (@as(u16, self.hdma1) << 8 | self.hdma2) & 0b1111111111110000;
    var dest = (@as(u16, self.hdma3) << 8 | self.hdma4) & 0b0001111111110000;
    // transfer 16 bytes per hblank which takes 8 M-cycles
    for (0..16) |_| {
        const value = self.bus.read_raw(source);
        self.bus.write_raw(dest, value);
        source += 1;
        dest += 1;
    }
    for (0..8) |_| {
        self.bus.timer.tick();
    }
    self.hdma1 = @intCast(source >> 8);
    self.hdma2 = @intCast(source & 0b11110000); // Lower 4 bits always masked
    self.hdma3 = @intCast((dest & 0b0001111111110000) >> 8);
    self.hdma4 = @intCast(dest & 0b11110000);

    if (self.hdma5.length == 0) {
        self.hblank_DMA = false;
        self.hdma5 = @bitCast(@as(u8, 0xFF)); // set HDMA5 to 0xFF when transfer is complete
    } else {
        self.hdma5.length -= 1;
    }
}

const std = @import("std");
/// perform general DMA at once
fn perform_general_DMA(self: *Dma) void {
    std.log.info("general DMA", .{});
    var source = (@as(u16, self.hdma1) << 8 | self.hdma2) & 0b1111111111110000;
    var dest = (@as(u16, self.hdma3) << 8 | self.hdma4) & 0b0001111111110000;
    const bytes = (self.hdma5.length + 1) << 4; // + 1 * 16 bytes
    for (0..bytes) |_| {
        const value = self.bus.read_raw(source);
        self.bus.write_raw(dest, value);
        source += 1;
        dest += 1;
    }
    // Each byte transfer takes 0.5 M-cycle
    for (0..bytes / 2) |_| {
        self.bus.timer.tick();
    }
    self.hdma1 = @intCast(source >> 8);
    self.hdma2 = @intCast(source & 0b11110000); // Lower 4 bits always masked
    self.hdma3 = @intCast((dest & 0b0001111111110000) >> 8);
    self.hdma4 = @intCast(dest & 0b11110000);
    self.hdma5 = @bitCast(@as(u8, 0xFF)); // set HDMA5 to 0xFF when transfer is complete
}

// Memory-mapped I/O read/write
pub fn read(self: *Dma, address: u16) u8 {
    return switch (address) {
        0xFF51 => self.hdma1, // HDMA1
        0xFF52 => self.hdma2, // HDMA2
        0xFF53 => self.hdma3, // HDMA3
        0xFF54 => self.hdma4, // HDMA4
        0xFF55 => @bitCast(self.hdma5), // HDMA5
        else => 0xFF,
    };
}

pub fn write(self: *Dma, address: u16, value: u8) void {
    switch (address) {
        0xFF51 => self.hdma1 = value, // HDMA1
        0xFF52 => self.hdma2 = value, // HDMA2
        0xFF53 => self.hdma3 = value, // HDMA3
        0xFF54 => self.hdma4 = value, // HDMA4
        0xFF55 => {
            self.hdma5 = @bitCast(value);
            self.start_dma_transfer();
        }, // HDMA5
        else => {},
    }
}
