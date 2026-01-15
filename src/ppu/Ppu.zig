const Ppu = @This();

const rl = @cImport({
    @cInclude("raylib.h");
});
const Bus = @import("../Bus.zig");
const Fetcher = @import("Fetcher.zig");

const Lcdc = packed struct {
    priority: bool = false,
    obj_enable: bool = false,
    obj_size: u1 = 0,
    bg_tile_map_area: u1 = 0,
    bg_window_tile_data_area: u1 = 0,
    window_enable: bool = false,
    window_tile_map_area: u1 = 0,
    lcd_ppu_enable: bool = false,
};

const Stat = packed struct {
    ppu_mode: u2 = 0,
    lyc_eq_ly: bool = false,
    mode0_interrupt: bool = false,
    mode1_interrupt: bool = false,
    mode2_interrupt: bool = false,
    lyc_interrupt: bool = false,
    _padding: u1 = 0,
};

pub const SCREEN_HEIGHT: f32 = 144;
pub const SCREEN_WIDTH: f32 = 160;

screen: [SCREEN_HEIGHT * SCREEN_WIDTH]rl.Color = @splat(rl.BLACK), // 144x160 pixels

// registers
lcdc: Lcdc = Lcdc{},
stat: Stat = Stat{},
scy: u8 = 0, // scroll Y
scx: u8 = 0, // scroll X
ly: u8 = 0, // current scanline
lyc: u8 = 0, // LY compare
wy: u8 = 0, // window Y position
wx: u8 = 0, // window X position plus 7

lx: usize = 0, // current pixel within the scanline
fetcher: Fetcher = undefined,
bus: *Bus, // reference to the bus for memory-mapped I/O

pub fn init(bus: *Bus) Ppu {
    var ppu = Ppu{ .bus = bus };
    ppu.fetcher = Fetcher.init(&ppu);
    return ppu;
}

const std = @import("std");
pub fn step(self: *Ppu, dots: usize) void {
    _ = self;
    _ = dots;
    // const lcdc = self.bus.io.getLcdc();
}

// Memory-mapped I/O read/write

pub fn read(self: *const Ppu, address: u16) u8 {
    return switch (address) {
        0xFF40 => @bitCast(self.lcdc),
        0xFF41 => @bitCast(self.stat),
        // 0xFF42 => self.bus.io.IOPorts[0x42], // SCY
        // 0xFF43 => self.bus.io.IOPorts[0x43], // SCX
        0xFF44 => self.ly,
        0xFF45 => self.lyc,
        else => 0,
    };
}

pub fn write(self: *Ppu, address: u16, value: u8) void {
    switch (address) {
        0xFF40 => self.lcdc = @bitCast(value),
        0xFF41 => self.stat = @bitCast(value),
        // 0xFF42 => self.bus.io.IOPorts[0x42] = value, // SCY
        // 0xFF43 => self.bus.io.IOPorts[0x43] = value, // SCX
        0xFF45 => self.lyc = value,
        else => {},
    }
}
