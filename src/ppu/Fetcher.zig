//! fetcher for the ppu
const Fetcher = @This();

const Ppu = @import("Ppu.zig");

const Task = enum {
    get_tile,
    get_tile_data_low,
    get_tile_data_high,
    sleep,
    push,
};

current_task: Task = .get_tile,
fetcher_y: u8 = 0,
fetcher_x: u8 = 0,
tile_index: u8 = 0,
tile_data_low: u8 = 0,
tile_data_high: u8 = 0,

pub fn init() Fetcher {
    return Fetcher{};
}

pub fn tick(self: *Fetcher, ppu: *Ppu) usize {
    switch (self.current_task) {
        .get_tile => {
            getTile(self, ppu);
            return 2;
        },
        .get_tile_data_low => {
            self.current_task = .get_tile_data_high;
            if (ppu.vram_blocked) {
                self.tile_data_low = 0xFF;
            } else {
                const address = tileIndexToAddress(self.tile_index, ppu);

                self.tile_data_low = ppu.bus.VRAM[address - 0x8000];
            }
            return 2;
        },
        .get_tile_data_high => {
            self.current_task = .sleep;
            if (ppu.vram_blocked) {
                self.tile_data_high = 0xFF;
            } else {
                const address = tileIndexToAddress(self.tile_index, ppu) + 1;

                self.tile_data_high = ppu.bus.VRAM[address - 0x8000];
            }
            return 2;
        },
        .sleep => {
            self.current_task = .push;
            return 2;
        },
        .push => {
            tryPush(self, ppu);
            return 2;
        },
    }
}

/// Determines which background/window tile to fetch pixels from
fn getTile(self: *Fetcher, ppu: *Ppu) void {
    self.current_task = .get_tile_data_low;
    if (ppu.vram_blocked) {
        self.tile_index = 0xFF;
        return;
    }

    const inside_window = (ppu.ly >= ppu.wy) and (ppu.lx + 7 >= ppu.wx);
    const use_high_map = (ppu.lcdc.bg_tile_map_area == 1 and !inside_window) or (ppu.lcdc.window_tile_map_area == 1 and inside_window);

    const tile_map: u16 = if (use_high_map) 0x9C00 else 0x9800;

    var map_x: u8 = 0;
    var map_y: u8 = 0;

    if (inside_window) {
        map_x = ppu.lx + 7 - ppu.wx;
        map_y = ppu.ly - ppu.wy;
    } else {
        map_x = ((ppu.scx / 8) + self.fetcher_x) & 0x1F;
        map_y = (ppu.ly + ppu.scy) & 0xFF;
    }

    const address = tile_map + (map_y * 32) + map_x;
    self.tile_index = ppu.bus.VRAM[address - 0x8000];
}

/// Attempts to push the fetched tile data into the background FIFO
fn tryPush(self: *Fetcher, ppu: *Ppu) void {
    if (ppu.fifo_bg.count != 0) {
        return;
    }

    ppu.fifo_bg.push(self.tile_data_low, self.tile_data_high) catch {
        unreachable;
    };
    self.current_task = .get_tile;
    self.fetcher_x += 1;
}

/// Converts a tile index to its corresponding address in VRAM
fn tileIndexToAddress(tile_index: u8, ppu: *Ppu) u16 {
    const row = ((ppu.ly + ppu.scy) % 8);
    var address = @as(u16, 0x8000) + (tile_index * 16) + (row * 2);
    if (ppu.lcdc.bg_window_tile_data_area == 0 and tile_index < 128) {
        address += 0x1000; // 0x8800 addressing
    }
    return address;
}
