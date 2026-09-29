//! PPU (Pixel Processing Unit) implementation
//! created with reference to https://github.com/ISSOtm/pandocs/blob/rendering-internals/src/Rendering_Internals.md
const Ppu = @This();

const rl = @import("raylib");
const Bus = @import("../Bus.zig");
const Fetcher = @import("Fetcher.zig");
const Fifo = @import("Fifo.zig");
const ppu_structs = @import("ppu_structs.zig");
const Lcdc = ppu_structs.Lcdc;
const Stat = ppu_structs.Stat;
const OamEntry = ppu_structs.OamEntry;

pub const SCREEN_HEIGHT: f32 = 144;
pub const SCREEN_WIDTH: f32 = 160;

VRAM: [0x2000 * 2]u8 = @splat(0), // 8KiB Video RAM switchable 0/1: 8000-9FFF
screen: [SCREEN_HEIGHT * SCREEN_WIDTH]rl.Color = @splat(rl.Color.black), // 144x160 pixels
// TODO: PROBLEMS WHEN UNINITIALIZED oam entry is looped over?
oam_buffer: [10]OamEntry = undefined, // buffer for up to 10 sprites per scanline
oam_count: u8 = 0, // number of sprites in the oam_buffer

// registers
lcdc: Lcdc = Lcdc{},
stat: Stat = Stat{},
scy: u8 = 0, // scroll Y
scx: u8 = 0, // scroll X
ly: u8 = 0, // current scanline
lyc: u8 = 0, // LY compare
wy: u8 = 0, // window Y position
wx: u8 = 0, // window X position plus 7

wy_trigger: bool = false, // whether window Y has been triggered
inside_window: bool = false, // whether fetcher is currently fetching window tiles
lcd_x: u8 = 0, // current pixel within the scanline
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
            .oam_scan => { // 80 dots
                const dots = self.oamScan();
                dots_used += dots;
                self.total_dots += dots;
                if (self.total_dots >= 80) {
                    if (!self.wy_trigger and self.ly == self.wy and self.lcdc.window_enable) {
                        self.wy_trigger = true;
                    }
                    self.inside_window = self.wy_trigger and self.lcdc.window_enable;
                    self.stat.ppu_mode = .drawing;
                    // std.debug.print("######################\n", .{});
                    // std.debug.print("OAM BUFFER: {any}\n\n\n", .{self.oam_buffer[0..self.oam_count]});
                    // std.debug.print("OAM: {any}\n", .{self.bus.OAM});
                }
            },
            .drawing => { // 172 - 289 dots
                const dots = self.fetcher.tick(self);
                // if (self.ly == 0) {
                //     std.debug.print(
                //         "LY={d} task={any} lcd_x={d} fifo={d}\n",
                //         .{ self.ly, self.fetcher.current_task, self.lcd_x, self.fifo_bg.count },
                //     );
                // }
                dots_used += dots;
                self.total_dots += dots;

                for (0..dots) |_| {
                    self.drawPixel() catch {
                        break;
                    };

                    if (self.lcd_x >= 160) {
                        self.stat.ppu_mode = .hblank;
                        self.checkInterrupts();
                        break;
                    }
                }
            },
            .hblank => { // 87 - 204 dots
                dots_used += 2;
                self.total_dots += 2;
                if (self.total_dots >= 456) {
                    // End of scanline
                    self.resetLine();
                    if (self.ly >= 144) {
                        self.stat.ppu_mode = .vblank;
                        self.checkInterrupts();
                        self.wy_trigger = false;
                        self.fetcher.wl_internal = 0;
                        // Trigger VBlank interrupt
                        self.bus.io.request_interrupt(.vblank);
                    } else {
                        self.stat.ppu_mode = .oam_scan;
                        self.checkInterrupts();
                    }
                }
            },
            .vblank => { // 4560 dots (10 scanlines)
                dots_used += 2;
                self.total_dots += 2;
                if (self.total_dots >= 456) {
                    // End of scanline
                    self.total_dots = 0;
                    self.incrementLy();
                    if (self.ly > 153) {
                        self.ly = 0;
                        self.stat.ppu_mode = .oam_scan;
                        // self.checkInterrupts();
                    }
                }
            },
        }
    }
}

/// Prepares PPU, FIFO, and Fetcher for the next scanline
pub fn resetLine(self: *Ppu) void {
    self.total_dots = 0;
    self.incrementLy();
    self.lcd_x = 0;
    self.oam_count = 0;
    self.fifo_bg.clear();
    self.fifo_obj.clear();
    self.fetcher.current_task = .get_tile;
    self.fetcher.fetcher_x = 0;
    // increment window line internal counter once if inside window
    if (self.inside_window) {
        self.fetcher.wl_internal += 1;
    }
    self.fetcher.inside_window = false;
    self.inside_window = false;
}

fn incrementLy(self: *Ppu) void {
    self.ly += 1;
    self.stat.lyc_eq_ly = self.ly == self.lyc;
    self.checkInterrupts();
}

fn checkInterrupts(self: *Ppu) void {
    // Mode interrupts
    const mode_interrupt = switch (self.stat.ppu_mode) {
        .hblank => self.stat.mode0_interrupt,
        .vblank => self.stat.mode1_interrupt,
        .oam_scan => self.stat.mode2_interrupt,
        .drawing => false,
    };

    const lyc_interrupt = self.stat.lyc_eq_ly and self.stat.lyc_interrupt;

    if (lyc_interrupt or mode_interrupt) {
        self.bus.io.request_interrupt(.stat);
    }
}

fn oamScan(self: *Ppu) usize {
    // OAM Scan takes 80 dots (2 dots per OAM entry)

    const offset = self.total_dots / 2;
    const entry = OamEntry{
        .y_position = self.bus.OAM[offset * 4 + 0],
        .x_position = self.bus.OAM[offset * 4 + 1],
        .tile_index = self.bus.OAM[offset * 4 + 2],
        .attributes = @bitCast(self.bus.OAM[offset * 4 + 3]),
    };

    if (self.oam_count < 10 and
        entry.y_position > self.ly + 16 and
        entry.y_position <= self.ly + 16 + 8 + (8 * @as(u8, self.lcdc.obj_size)))
    {
        self.oam_buffer[self.oam_count] = entry;
        self.oam_count += 1;
    }

    return 2;
}

fn drawPixel(self: *Ppu) !void {
    if (self.lcdc.obj_enable) {
        for (self.oam_buffer[0..self.oam_count]) |sprite| {
            if (self.lcd_x == sprite.x_position - 8) {
                // std.debug.print("OAMENTRY: ", .{});
                // std.debug.print("{any}\n", .{sprite});
                // Calculate which row of the sprite we are on
                var line_y: u16 = self.ly + 16 - sprite.y_position;

                // Handle Y-Flip (Bit 6)
                if (sprite.attributes.y_flip) {
                    const sprite_height: u16 = if (self.lcdc.obj_size == 1) 16 else 8;
                    line_y = (sprite_height - 1) - line_y;
                }

                const bank = sprite.attributes.vram_bank;
                const address = @as(u16, 0x8000) + sprite.tile_index * 16 + (line_y * 2);

                const tile_data_low = self.readVram(bank, address);
                const tile_data_high = self.readVram(bank, address + 1);

                // std.debug.print("address: {any} {any}\n", .{ address, address + 1 });
                // std.debug.print("tile_data: {any} {any}\n", .{ tile_data_low, tile_data_high });
                // std.debug.print("vram: {any}\n", .{self.VRAM});

                self.fifo_obj.mix(
                    tile_data_low,
                    tile_data_high,
                    sprite.attributes.x_flip,
                    sprite.attributes.priority,
                );
            }
        }
    }

    const bg_pixel = try self.fifo_bg.pop();
    var final_pixel = bg_pixel;

    if (self.fifo_obj.count > 0) {
        // std.debug.print("{any}: {any}\n", .{ self.lcd_x, self.fifo_obj.buffer });
        const obj_pixel = try self.fifo_obj.pop();

        if (obj_pixel.color_index != 0) {
            std.debug.print("OBJ PIXEL\n", .{});
            if (!obj_pixel.background_priority or bg_pixel.color_index == 0) {
                final_pixel = obj_pixel;
            }
        }
    }

    const color = switch (final_pixel.color_index) {
        0 => rl.Color.ray_white,
        1 => rl.Color.light_gray,
        2 => rl.Color.dark_gray,
        3 => rl.Color.black,
    };
    self.screen[@as(usize, self.ly) * @as(usize, SCREEN_WIDTH) + @as(usize, self.lcd_x)] = color;
    self.lcd_x += 1;
}

// VRAM read/write
pub fn readVram(self: *const Ppu, bank: u1, address: u16) u8 {
    return self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)];
}

pub fn writeVram(self: *Ppu, bank: u1, address: u16, value: u8) void {
    // if (self.bus.boot_rom_enabled and address >= 0x8000 and address < 0x8020) {
    //     std.debug.print(
    //         "boot VRAM bank={d} address=${X} value=${X}\n",
    //         .{ bank, address, value },
    //     );
    // }
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
        0xFF46 => 0, // OAM DMA is write-only
        0xFF4A => self.wy,
        0xFF4B => self.wx,
        else => 0,
    };
}

pub fn write(self: *Ppu, address: u16, value: u8) void {
    switch (address) {
        0xFF40 => {
            const lcdc: Lcdc = @bitCast(value);
            // std.debug.print(
            //     "LCDC=${X} LY={d} mode={d}\n",
            //     .{ value, self.ly, @intFromEnum(self.stat.ppu_mode) },
            // );
            self.lcdc = lcdc;
        },
        0xFF41 => {
            var new_stat: ppu_structs.Stat = @bitCast(value);
            new_stat.lyc_eq_ly = self.stat.lyc_eq_ly; // LYC=LY flag is read-only
            new_stat.ppu_mode = self.stat.ppu_mode; // mode bits are read-only

            self.stat = new_stat;
        },
        0xFF42 => self.scy = value,
        0xFF43 => self.scx = value,
        0xFF44 => {}, // LY is read-only
        0xFF45 => {
            self.lyc = value;
            self.checkInterrupts();
        },
        0xFF46 => self.bus.dma.startTransfer(value), // enable OAM DMA transfer mode
        0xFF4A => self.wy = value,
        0xFF4B => self.wx = value,
        else => {},
    }
}
