//! fetcher for the ppu
const Fetcher = @This();

const Ppu = @import("Ppu.zig");
const OamAttributes = @import("ppu_structs.zig").OamAttributes;

const Task = enum {
    get_tile,
    get_tile_data_low,
    get_tile_data_high,
    sleep,
    push,
};

current_task: Task = .get_tile,
fetcher_x: u8 = 0, // current x position of the fetcher in pixels
wl_internal: u8 = 0, // internal window line counter
tile_id: u8 = 0,
tile_attributes: OamAttributes = OamAttributes{},
tile_data_low: u8 = 0,
tile_data_high: u8 = 0,
inside_window: bool = false, // whether the fetcher is currently fetching window tiles

pub fn init() Fetcher {
    return Fetcher{};
}

pub fn tick(self: *Fetcher, ppu: *Ppu) usize {
    switch (self.current_task) {
        .get_tile => {
            self.current_task = .get_tile_data_low;
            self.tile_id, self.tile_attributes = get_tile_id(self, ppu);
            return 2;
        },
        .get_tile_data_low => {
            self.current_task = .get_tile_data_high;
            const address = self.tile_index_to_address(ppu);

            // TODO: handle vertical flip
            self.tile_data_low = ppu.read_vram(self.tile_attributes.vram_bank, address);
            return 2;
        },
        .get_tile_data_high => {
            self.current_task = .sleep;
            const address = self.tile_index_to_address(ppu) + 1;

            // TODO: handle vertical flip
            self.tile_data_high = ppu.read_vram(self.tile_attributes.vram_bank, address);

            // The high-plane phase is also a push opportunity.
            _ = try_push(self, ppu);
            return 2;
        },
        .sleep => {
            // do nothing
            self.current_task = .push;
            return 2;
        },
        .push => {
            if (try_push(self, ppu)) {
                self.current_task = .get_tile;
            }
            return 1;
        },
    }
}

/// Determines which background/window tile to fetch pixels from
fn get_tile_id(self: *Fetcher, ppu: *Ppu) struct { u8, OamAttributes } {
    if (!self.inside_window) {
        self.inside_window = ppu.inside_window and (self.fetcher_x + 7 >= ppu.wx);
        if (self.inside_window) {
            ppu.fifo_bg.clear();
        }
    }

    const window_y = if (self.inside_window) self.wl_internal else 0;

    const base = 0x9800;
    // 0x9800: 0b1001100000000000
    // 0x9C00: 0b1001110000000000
    // bit 10 determines which base address to use for the tile map
    const bit10 = if (self.inside_window) ppu.lcdc.window_tile_map_area else ppu.lcdc.bg_tile_map_area;

    // >> 3 is the same as /8
    // calculate the tile map coordinates based on the current fetcher position and scroll/window position
    const map_y = if (self.inside_window) window_y >> 3 else (ppu.ly +% ppu.scy) >> 3;
    const map_x = if (self.inside_window)
        (self.fetcher_x >> 3) & 0x1F
    else
        ((self.fetcher_x +% ppu.scx) >> 3) & 0x1F;

    // calculate the address of the tile ID in VRAM based on the tile map coordinates and base address
    const address = base | (@as(u16, bit10) << 10) | (@as(u16, map_y) << 5) | @as(u16, map_x);
    return .{ ppu.read_vram(0, address), @bitCast(ppu.read_vram(1, address)) };
}

/// Attempts to push the fetched tile data into the background FIFO
fn try_push(self: *Fetcher, ppu: *Ppu) bool {
    ppu.fifo_bg.push(self.tile_data_low, self.tile_data_high, self.tile_attributes) catch {
        return false;
    };
    self.fetcher_x += 8;
    return true;
}

/// Converts a tile index to its corresponding address in VRAM
fn tile_index_to_address(self: *const Fetcher, ppu: *const Ppu) u16 {
    const window_y = if (self.inside_window) self.wl_internal else 0;

    const base = 0x8000;
    // 0x8000: 0b1000000000000000
    // 0x9000: 0b1001000000000000
    // bit 12 determines which base address to use for the tile data
    const bit12 = if (ppu.lcdc.bg_window_tile_data_area == 1) 0 else (~self.tile_id >> 7);

    // calculate the row offset within the tile based on the current fetcher position and scroll/window position
    var row_offset = if (self.inside_window) window_y % 8 else (ppu.ly +% ppu.scy) % 8;
    // handle y-flip
    if (self.tile_attributes.y_flip) {
        row_offset = 7 - row_offset;
    }

    // calculate the address of the tile data in VRAM based on the tile index, base address, and row offset
    const address = base | (@as(u16, bit12) << 12) | (@as(u16, self.tile_id & 0x7F) << 4) | (@as(u16, row_offset) << 1);

    return address;
}
