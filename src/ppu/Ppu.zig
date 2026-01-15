const Ppu = @This();

const rl = @cImport({
    @cInclude("raylib.h");
});
const Bus = @import("../Bus.zig");
const Fetcher = @import("Fetcher.zig");
const Fifo = @import("Fifo.zig");

pub const SCREEN_HEIGHT: f32 = 144;
pub const SCREEN_WIDTH: f32 = 160;

const Lcdc = packed struct {
    priority: bool = false, // 0
    obj_enable: bool = false, // 1
    obj_size: u1 = 0, // 2
    bg_tile_map_area: u1 = 0, // 3
    bg_window_tile_data_area: u1 = 0, // 4
    window_enable: bool = false, // 5
    window_tile_map_area: u1 = 0, // 6
    lcd_ppu_enable: bool = false, // 7
};

const Stat = packed struct {
    ppu_mode: u2 = 0, // 0-1
    lyc_eq_ly: bool = false, // 2
    mode0_interrupt: bool = false, // 3
    mode1_interrupt: bool = false, // 4
    mode2_interrupt: bool = false, // 5
    lyc_interrupt: bool = false, // 6
    _padding: u1 = 0,
};

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

lx: u8 = 0, // current pixel within the scanline
fetcher_bg: Fetcher = Fetcher.init(),
fetcher_obj: Fetcher = Fetcher.init(),
vram_blocked: bool = false,

fifo_bg: Fifo = Fifo.init(),
fifo_obj: Fifo = Fifo.init(),
bus: *Bus, // reference to the bus for memory-mapped I/O

pub fn init(bus: *Bus) Ppu {
    return Ppu{ .bus = bus };
}

const std = @import("std");
pub fn step(self: *Ppu, cycles: usize) void {
    var dots_used: usize = 0;

    while (dots_used < cycles) {
        const dots = self.fetcher_bg.tick(self);
        dots_used += dots;
    }
}

// Memory-mapped I/O read/write

pub fn read(self: *const Ppu, address: u16) u8 {
    return switch (address) {
        0xFF40 => @bitCast(self.lcdc),
        0xFF41 => @bitCast(self.stat),
        0xFF42 => self.scy,
        0xFF43 => self.scx,
        0xFF44 => self.ly,
        0xFF45 => self.lyc,
        0xFF4A => self.wy,
        0xFF4B => self.wx,
        else => 0,
    };
}

pub fn write(self: *Ppu, address: u16, value: u8) void {
    switch (address) {
        0xFF40 => self.lcdc = @bitCast(value),
        0xFF41 => self.stat = @bitCast(value),
        0xFF42 => self.scy = value,
        0xFF43 => self.scx = value,
        0xFF44 => {}, // LY is read-only
        0xFF45 => self.lyc = value,
        0xFF4A => self.wy = value,
        0xFF4B => self.wx = value,
        else => {},
    }
}
