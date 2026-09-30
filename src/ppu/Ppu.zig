//! PPU (Pixel Processing Unit) implementation
//! created with reference to https://github.com/ISSOtm/pandocs/blob/rendering-internals/src/Rendering_Internals.md
const Ppu = @This();

const Bus = @import("../Bus.zig");
const Fetcher = @import("Fetcher.zig");
const Fifo = @import("Fifo.zig");
const ppu_structs = @import("ppu_structs.zig");
const Lcdc = ppu_structs.Lcdc;
const Stat = ppu_structs.Stat;
const OamEntry = ppu_structs.OamEntry;
const Bgpi = ppu_structs.Bgpi;
const Obpi = ppu_structs.Obpi;

pub const SCREEN_HEIGHT: f32 = 144;
pub const SCREEN_WIDTH: f32 = 160;

VRAM: [0x2000 * 2]u8 = @splat(0), // 8KiB Video RAM switchable 0/1: 8000-9FFF
OAM: [0xA0]u8 = @splat(0), // Object Attribute Memory (OAM): FE00-FE9F
screen: [SCREEN_HEIGHT * SCREEN_WIDTH]u32 = @splat(0xFF000000), // 144x160 pixels
// TODO: PROBLEMS WHEN UNINITIALIZED oam entry is looped over?
oam_buffer: [10]OamEntry = undefined, // buffer for up to 10 sprites per scanline
oam_count: u8 = 0, // number of sprites in the oam_buffer

bg_CRAM: [64]u8 = @splat(0), // 64 bytes of background Color RAM
obj_CRAM: [64]u8 = @splat(0), // 64 bytes of object Color RAM
bgpi: Bgpi = Bgpi{}, // background palette index
obpi: Obpi = Obpi{}, // object palette index

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
frame_complete: bool = false, // whether the current frame has been completed

fetcher: Fetcher = Fetcher.init(),
fifo_bg: Fifo = Fifo.init(),
fifo_obj: Fifo = Fifo.init(),
bus: *Bus, // reference to the bus for memory-mapped I/O

pub fn init(bus: *Bus) Ppu {
    return Ppu{ .bus = bus };
}

const std = @import("std");
pub fn step(self: *Ppu, cycles: usize) void {
    if (!self.lcdc.lcd_ppu_enable) return; // PPU does not run when LCD is disabled
    var dots_used: usize = 0;

    while (dots_used < cycles) {
        switch (self.stat.ppu_mode) {
            .oam_scan => { // 80 dots
                const dots = self.oam_scan();
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
                    // std.debug.print("OAM: {any}\n", .{self.OAM});
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
                    self.draw_pixel() catch {
                        break;
                    };

                    if (self.lcd_x >= 160) {
                        self.stat.ppu_mode = .hblank;
                        self.check_interrupts();
                        break;
                    }
                }
            },
            .hblank => { // 87 - 204 dots
                dots_used += 2;
                self.total_dots += 2;
                if (self.total_dots >= 456) {
                    // End of scanline
                    self.reset_line();
                    if (self.ly >= 144) {
                        self.stat.ppu_mode = .vblank;
                        self.check_interrupts();
                        self.wy_trigger = false;
                        self.fetcher.wl_internal = 0;
                        // Trigger VBlank interrupt
                        self.bus.io.request_interrupt(.vblank);
                        self.frame_complete = true;
                    } else {
                        self.stat.ppu_mode = .oam_scan;
                        self.check_interrupts();
                    }
                }
            },
            .vblank => { // 4560 dots (10 scanlines)
                dots_used += 2;
                self.total_dots += 2;
                if (self.total_dots >= 456) {
                    // End of scanline
                    self.total_dots = 0;
                    self.increment_ly();
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
pub fn reset_line(self: *Ppu) void {
    self.total_dots = 0;
    self.increment_ly();
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

fn increment_ly(self: *Ppu) void {
    self.ly += 1;
    self.stat.lyc_eq_ly = self.ly == self.lyc;
    self.check_interrupts();
}

fn check_interrupts(self: *Ppu) void {
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

fn oam_scan(self: *Ppu) usize {
    // OAM Scan takes 80 dots (2 dots per OAM entry)

    const offset = self.total_dots / 2;
    const entry = OamEntry{
        .y_position = self.OAM[offset * 4 + 0],
        .x_position = self.OAM[offset * 4 + 1],
        .tile_index = self.OAM[offset * 4 + 2],
        .attributes = @bitCast(self.OAM[offset * 4 + 3]),
    };

    const obj_height: u8 = if (self.lcdc.obj_size == 1) 16 else 8;

    if (self.oam_count < 10 and
        self.ly + 16 >= entry.y_position and
        self.ly + 16 < entry.y_position + obj_height)
    {
        self.oam_buffer[self.oam_count] = entry;
        self.oam_count += 1;
    }

    return 2;
}

fn draw_pixel(self: *Ppu) !void {
    if (self.lcdc.obj_enable) {
        for (self.oam_buffer[0..self.oam_count]) |sprite| {
            if (self.lcd_x == @as(i32, sprite.x_position) - 8) {
                // Calculate which row of the sprite we are on
                var line_y: u16 = self.ly + 16 - sprite.y_position;

                // Handle Y-Flip (Bit 6)
                if (sprite.attributes.y_flip) {
                    const sprite_height: u16 = if (self.lcdc.obj_size == 1) 16 else 8;
                    line_y = (sprite_height - 1) - line_y;
                }

                const bank = sprite.attributes.vram_bank;
                const address = @as(u16, 0x8000) + @as(u16, sprite.tile_index) * 16 + (line_y * 2);

                const tile_data_low = self.read_vram(bank, address);
                const tile_data_high = self.read_vram(bank, address + 1);

                self.fifo_obj.mix(
                    tile_data_low,
                    tile_data_high,
                    sprite.attributes,
                );
            }
        }
    }

    const bg_pixel = try self.fifo_bg.pop();
    var final_pixel = bg_pixel;
    var is_obj = false;

    if (self.fifo_obj.count > 0) {
        const obj_pixel = try self.fifo_obj.pop();
        if (obj_pixel.color_index != 0) {
            const bg_transparent = bg_pixel.color_index == 0;
            const bg_priority = bg_pixel.background_priority;
            const obj_priority = obj_pixel.background_priority;
            const master_priority = self.lcdc.priority; // LCDC Bit 0

            // if lcdc.0 is 0, sprites always win.
            // otherwise, OBJ wins if BG is transparent, or if neither BG nor OBJ has priority.
            if (!master_priority or bg_transparent or (!bg_priority and !obj_priority)) {
                final_pixel = obj_pixel;
                is_obj = true;
            }
        }
    }

    const color = self.resolve_cgb_color(final_pixel.color_index, final_pixel.palette, is_obj);
    self.screen[@as(usize, self.ly) * @as(usize, SCREEN_WIDTH) + @as(usize, self.lcd_x)] = color;
    self.lcd_x += 1;
}

// ==================== PPU access ====================
// always accessible
// VRAM read/write
pub fn read_vram(self: *const Ppu, bank: u1, address: u16) u8 {
    return self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)];
}

pub fn write_vram(self: *Ppu, bank: u1, address: u16, value: u8) void {
    self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)] = value;
}

// OAM read/write
pub fn read_oam(self: *const Ppu, address: u16) u8 {
    return self.OAM[address - 0xFE00];
}

pub fn write_oam(self: *Ppu, address: u16, value: u8) void {
    self.OAM[address - 0xFE00] = value;
}

// CRAM read/write
pub fn read_cram(self: *const Ppu, address: u16) u8 {
    if (address == 0xFF69) return self.bg_CRAM[self.bgpi.address] else if (address == 0xFF6B) return self.obj_CRAM[self.obpi.address] else unreachable;
}

pub fn write_cram(self: *Ppu, address: u16, value: u8) void {
    if (address == 0xFF69) {
        self.bg_CRAM[self.bgpi.address] = value;
        if (self.bgpi.auto_increment) {
            self.bgpi.address +%= 1;
        }
    } else if (address == 0xFF6B) {
        self.obj_CRAM[self.obpi.address] = value;
        if (self.obpi.auto_increment) {
            self.obpi.address +%= 1;
        }
    } else unreachable;
}
// ====================================================

// ==================== CPU access ====================
// not accessible for some modes
// VRAM read/write
// VRAM not accessible during mode 3 (drawing)
pub fn read_vram_cpu(self: *const Ppu, bank: u1, address: u16) u8 {
    // return 0xFF if VRAM is not accessible
    return if (self.stat.ppu_mode == .drawing) 0xFF else self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)];
}

pub fn write_vram_cpu(self: *Ppu, bank: u1, address: u16, value: u8) void {
    // ignore writes if VRAM is not accessible
    if (self.stat.ppu_mode == .drawing) return;
    self.VRAM[address - 0x8000 + (@as(u16, bank) * 0x2000)] = value;
}

// OAM read/write
// OAM not accessible during mode 2 and 3 (drawing)
pub fn read_oam_cpu(self: *const Ppu, address: u16) u8 {
    // return 0xFF if VRAM is not accessible
    return if (self.stat.ppu_mode == .drawing or self.stat.ppu_mode == .oam_scan) 0xFF else self.OAM[address - 0xFE00];
}

pub fn write_oam_cpu(self: *Ppu, address: u16, value: u8) void {
    // ignore writes if OAM is not accessible
    if (self.stat.ppu_mode == .drawing or self.stat.ppu_mode == .oam_scan) return;
    self.OAM[address - 0xFE00] = value;
}

// CRAM read/write
// CRAM not accessible during mode 3 (drawing)
pub fn read_cram_cpu(self: *const Ppu, address: u16) u8 {
    // return 0xFF if CRAM is not accessible
    if (self.stat.ppu_mode == .drawing) return 0xFF;
    if (address == 0xFF69) return self.bg_CRAM[self.bgpi.address] else if (address == 0xFF6B) return self.obj_CRAM[self.obpi.address] else unreachable;
}

pub fn write_cram_cpu(self: *Ppu, address: u16, value: u8) void {
    // ignore writes if CRAM is not accessible
    if (self.stat.ppu_mode == .drawing) return;
    if (address == 0xFF69) {
        self.bg_CRAM[self.bgpi.address] = value;
        if (self.bgpi.auto_increment) {
            self.bgpi.address +%= 1;
        }
    } else if (address == 0xFF6B) {
        self.obj_CRAM[self.obpi.address] = value;
        if (self.obpi.auto_increment) {
            self.obpi.address +%= 1;
        }
    } else unreachable;
}
// ====================================================

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
        0xFF68 => @bitCast(self.bgpi),
        0xFF6A => @bitCast(self.obpi),
        0xFF69, 0xFF6B => self.read_cram_cpu(address),
        else => 0,
    };
}

pub fn write(self: *Ppu, address: u16, value: u8) void {
    switch (address) {
        0xFF40 => {
            const new_lcdc: Lcdc = @bitCast(value);
            if (self.lcdc.lcd_ppu_enable and !new_lcdc.lcd_ppu_enable) {
                // LCD is turning off: reset ppu state
                self.ly = 0;
                self.total_dots = 0;
                self.stat.ppu_mode = .hblank; // Mode 0
            }
            self.lcdc = new_lcdc;
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
            self.check_interrupts();
        },
        0xFF46 => self.bus.dma.startTransfer(value), // enable OAM DMA transfer mode
        0xFF4A => self.wy = value,
        0xFF4B => self.wx = value,
        0xFF68 => self.bgpi = @bitCast(value),
        0xFF6A => self.obpi = @bitCast(value),
        0xFF69, 0xFF6B => self.write_cram_cpu(address, value),
        else => {},
    }
}

fn resolve_cgb_color(self: *const Ppu, color_idx: u2, palette_idx: u3, is_obj: bool) u32 {
    const ram = if (is_obj) &self.obj_CRAM else &self.bg_CRAM;
    const base_addr = (@as(usize, palette_idx) * 8) + (@as(usize, color_idx) * 2);
    const color_data = @as(u16, ram[base_addr]) | (@as(u16, ram[base_addr + 1]) << 8);

    const r_5: u32 = color_data & 0x1F;
    const g_5: u32 = (color_data >> 5) & 0x1F;
    const b_5: u32 = (color_data >> 10) & 0x1F;

    const r: u32 = (r_5 * 255) / 31;
    const g: u32 = (g_5 * 255) / 31;
    const b: u32 = (b_5 * 255) / 31;

    // Convert RGB555 to RGB888
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}
