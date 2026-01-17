//! fetcher for the ppu
const Fetcher = @This();

const Ppu = @import("Ppu.zig");

const Task = enum {
    get_tile,
    get_tile_data_low,
    get_tile_data_high,
    push,
};

current_task: Task = .get_tile,
fetcher_x: u8 = 0, // current x position of the fetcher in pixels
wl_internal: u8 = 0, // internal window line counter
tile_id: u8 = 0,
tile_data_low: u8 = 0,
tile_data_high: u8 = 0,
inside_window: bool = false, // whether the fetcher is currently fetching window tiles

pub fn init() Fetcher {
    return Fetcher{};
}

pub fn tick(self: *Fetcher, ppu: *Ppu) usize {
    switch (self.current_task) {
        .get_tile => {
            self.tile_id = getTileId(self, ppu);
            return 2;
        },
        .get_tile_data_low => {
            self.current_task = .get_tile_data_high;
            if (ppu.vram_blocked) {
                self.tile_data_low = 0xFF;
            } else {
                const address = self.tileIndexToAddress(ppu);

                self.tile_data_low = ppu.readVram(0, address);
            }
            return 2;
        },
        .get_tile_data_high => {
            self.current_task = .push;
            if (ppu.vram_blocked) {
                self.tile_data_high = 0xFF;
            } else {
                const address = self.tileIndexToAddress(ppu) + 1;

                self.tile_data_high = ppu.readVram(0, address);
            }
            return 2;
        },
        .push => {
            tryPush(self, ppu);
            return 2;
        },
    }
}

/// Determines which background/window tile to fetch pixels from
fn getTileId(self: *Fetcher, ppu: *Ppu) u8 {
    self.current_task = .get_tile_data_low;
    if (ppu.vram_blocked) {
        return 0xFF;
    }

    if (!self.inside_window) {
        self.inside_window = ppu.inside_window and (self.fetcher_x + 7 >= ppu.wx);
        if (self.inside_window) {
            self.wl_internal += 1;
            ppu.fifo_bg.clear();
        }
    }

    const window_y = if (self.inside_window) self.wl_internal - 1 else 0;

    const base = 0x9800;
    const bit10 = if (self.inside_window) ppu.lcdc.window_tile_map_area else ppu.lcdc.bg_tile_map_area;
    // >> 3 is the same as /8
    const map_y = if (self.inside_window) window_y >> 3 else (ppu.ly +% ppu.scy) >> 3;
    const map_x = if (self.inside_window) self.fetcher_x >> 3 else (self.fetcher_x +% ppu.scx) >> 3;

    const address = base | (@as(u16, bit10) << 10) | (@as(u16, map_y) << 5) | @as(u16, map_x);
    return ppu.readVram(0, address);
}

/// Attempts to push the fetched tile data into the background FIFO
fn tryPush(self: *Fetcher, ppu: *Ppu) void {
    ppu.fifo_bg.push(self.tile_data_low, self.tile_data_high) catch {
        return;
    };
    self.current_task = .get_tile;
    self.fetcher_x += 8;
}

/// Converts a tile index to its corresponding address in VRAM
fn tileIndexToAddress(self: *const Fetcher, ppu: *Ppu) u16 {
    const window_y = if (self.inside_window) self.wl_internal - 1 else 0;

    const base = 0x8000;
    const bit12 = if (ppu.lcdc.bg_window_tile_data_area == 1) 0 else (~self.tile_id >> 7);
    const row_offset = if (self.inside_window) window_y % 8 else (ppu.ly +% ppu.scy) % 8;

    const address = base | (@as(u16, bit12) << 12) | (@as(u16, self.tile_id & 0x7F) << 4) | (@as(u16, row_offset) << 1);

    return address;
}
