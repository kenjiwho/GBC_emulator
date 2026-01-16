//! PPU (Pixel Processing Unit) implementation
//! created with reference to https://github.com/ISSOtm/pandocs/blob/rendering-internals/src/Rendering_Internals.md
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

const PpuMode = enum(u2) {
    hblank = 0,
    vblank = 1,
    oam_scan = 2,
    drawing = 3,
};

const Stat = packed struct {
    ppu_mode: PpuMode = PpuMode.oam_scan, // 0-1
    lyc_eq_ly: bool = false, // 2
    mode0_interrupt: bool = false, // 3
    mode1_interrupt: bool = false, // 4
    mode2_interrupt: bool = false, // 5
    lyc_interrupt: bool = false, // 6
    _padding: u1 = 0,
};

VRAM: [0x2000 * 2]u8 = @splat(0), // 8KiB Video RAM switchable 0/1: 8000-9FFF
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
vram_blocked: bool = false,
total_dots: usize = 0, // total dots elapsed in current scanline

fetcher: Fetcher = Fetcher.init(),
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
        switch (self.stat.ppu_mode) {
            .oam_scan => {
                // OAM Scan
                const dots = self.oamScan();
                dots_used += dots;
                self.total_dots += dots;
                if (self.total_dots >= 80) {
                    self.stat.ppu_mode = .drawing;
                }
            },
            .drawing => {
                // Pixel Drawing
                const dots = self.fetcher.tick(self);
                dots_used += dots;

                for (0..dots) |_| {
                    // Drawing pixels
                    const pixel = self.fifo_bg.pop() catch {
                        break;
                    };

                    const color = switch (pixel.color_index) {
                        0 => rl.RAYWHITE,
                        1 => rl.LIGHTGRAY,
                        2 => rl.DARKGRAY,
                        3 => rl.BLACK,
                    };
                    self.screen[@as(usize, self.ly) * @as(usize, SCREEN_WIDTH) + @as(usize, self.lx)] = color;
                    self.lx += 1;

                    if (self.lx >= 160) {
                        // End of scanline
                        self.stat.ppu_mode = .hblank;
                        self.total_dots = 0;
                        self.lx = 0;
                        self.fifo_bg.clear();
                        self.fetcher.current_task = .get_tile;
                        break;
                    }
                }
            },
            .hblank => {
                // HBlank
                dots_used += 2;
                self.total_dots += 2;
                if (self.total_dots >= 456) {
                    self.total_dots = 0;
                    self.ly += 1;
                    if (self.ly >= 144) {
                        self.stat.ppu_mode = .vblank;
                        // Trigger VBlank interrupt
                        self.bus.io.requestInterrupt(.vblank);
                    } else {
                        self.stat.ppu_mode = .oam_scan;
                    }
                }
            },
            .vblank => {
                // VBlank
                dots_used += 2;
                self.total_dots += 2;
                if (self.total_dots >= 456) {
                    self.total_dots = 0;
                    self.ly += 1;
                    if (self.ly > 153) {
                        self.ly = 0;
                        self.stat.ppu_mode = .oam_scan;
                    }
                }
            },
        }
    }
}

fn oamScan(self: *Ppu) usize {
    _ = self;
    // OAM Scan takes 80 dots
    return 2;
}

// VRAM read/write
pub fn readVram(self: *const Ppu, bank: u1, address: u16) u8 {
    return self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)];
}

pub fn writeVram(self: *Ppu, bank: u1, address: u16, value: u8) void {
    self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)] = value;
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
