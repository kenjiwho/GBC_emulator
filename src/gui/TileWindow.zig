//! Views all VRAM tiles in one view
const TileWindow = @This();

const zsdl3 = @import("zsdl3");
const Gbc = @import("../core/Gbc.zig");
const AppActions = @import("WindowManager.zig").AppActions;

const TILE_WIDTH = 16;
const TILE_HEIGHT = 24;
const TILES_PER_ROW = 16;
const TILE_ROWS = 24;
const CELL_SIZE = 9;
const PIXEL_WIDTH = (TILES_PER_ROW * 2) * CELL_SIZE; // * 2 for both banks
const PIXEL_HEIGHT = TILE_ROWS * CELL_SIZE;
const GRID_COLOR: u32 = 0xFF333333;

gbc: *Gbc,
window: *zsdl3.SDL_Window = undefined,
renderer: *zsdl3.SDL_Renderer = undefined,
texture: *zsdl3.SDL_Texture = undefined,
pixels: [PIXEL_WIDTH * PIXEL_HEIGHT]u32 = @splat(GRID_COLOR),

pub fn init(gbc: *Gbc) !TileWindow {
    var tile_window = TileWindow{ .gbc = gbc };

    tile_window.window = zsdl3.createWindow(
        "Tile window",
        PIXEL_WIDTH,
        PIXEL_HEIGHT,
        zsdl3.SDL_WINDOW_RESIZABLE,
    ) orelse return error.SDLWindowFailed;

    tile_window.renderer = zsdl3.createRenderer(tile_window.window, null) orelse return error.SDLRendererFailed;
    _ = zsdl3.setRenderLogicalPresentation(
        tile_window.renderer,
        PIXEL_WIDTH,
        PIXEL_HEIGHT,
        zsdl3.SDL_LOGICAL_PRESENTATION_LETTERBOX,
    );

    tile_window.texture = zsdl3.createTexture(
        tile_window.renderer,
        zsdl3.SDL_PIXELFORMAT_ARGB8888,
        zsdl3.SDL_TEXTUREACCESS_STREAMING,
        PIXEL_WIDTH,
        PIXEL_HEIGHT,
    ) orelse return error.SDLTextureFailed;
    _ = zsdl3.setTextureScaleMode(tile_window.texture, zsdl3.SDL_SCALEMODE_NEAREST);

    return tile_window;
}

pub fn deinit(self: *const TileWindow) void {
    zsdl3.destroyTexture(self.texture);
    zsdl3.destroyRenderer(self.renderer);
    zsdl3.destroyWindow(self.window);
}

pub fn get_id(self: *const TileWindow) u32 {
    return zsdl3.getWindowID(self.window);
}

pub fn handle_event(self: *const TileWindow, event: zsdl3.SDL_Event) AppActions {
    _ = self;
    var actions = AppActions{};
    switch (event.type) {
        zsdl3.SDL_EVENT_WINDOW_CLOSE_REQUESTED => actions.toggle_debug = true,
        zsdl3.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                zsdl3.SDLK_n => actions.single_step = true,
                else => {},
            }
        },
        else => {},
    }
    return actions;
}

/// decode tiles from VRAM and draw to texture
pub fn render(self: *TileWindow) void {
    // Build the palette lookup table for this frame
    const palettes = self.guess_palettes();

    for (0..2) |bank| {
        for (0..384) |tile_idx| {
            const bank_x_offset = bank * TILES_PER_ROW;
            const tile_x = (bank_x_offset + (tile_idx % TILES_PER_ROW)) * CELL_SIZE;
            const tile_y = (tile_idx / TILES_PER_ROW) * CELL_SIZE;

            const guess = palettes[bank][tile_idx];

            for (0..8) |row| {
                const addr = 0x8000 + @as(u16, @intCast(tile_idx)) * 16 + @as(u16, @intCast(row)) * 2;
                const bank_u1: u1 = @intCast(bank);

                const low = self.gbc.ppu.read_vram(bank_u1, addr);
                const high = self.gbc.ppu.read_vram(bank_u1, addr + 1);

                for (0..8) |col| {
                    const bit_idx: u3 = @intCast(7 - col);
                    const color_idx: u2 = @intCast(((high >> bit_idx) & 1) << 1 | ((low >> bit_idx) & 1));

                    var final_color: u32 = 0;

                    if (guess) |g| {
                        // If we guessed a palette, read the true CGB color
                        switch (g) {
                            .bg => |pal| final_color = self.gbc.ppu.resolve_cgb_color(color_idx, pal, false),
                            .obj => |pal| final_color = self.gbc.ppu.resolve_cgb_color(color_idx, pal, true),
                        }
                    } else {
                        // If the tile is completely unused, fallback to grayscale
                        final_color = switch (color_idx) {
                            0 => 0xFFFFFFFF,
                            1 => 0xFFAAAAAA,
                            2 => 0xFF555555,
                            3 => 0xFF000000,
                        };
                    }

                    const px = tile_x + col;
                    const py = tile_y + row;
                    self.pixels[py * PIXEL_WIDTH + px] = final_color;
                }
            }
        }
    }

    _ = zsdl3.renderClear(self.renderer);
    _ = zsdl3.updateTexture(self.texture, null, &self.pixels, PIXEL_WIDTH * 4);
    _ = zsdl3.renderTexture(self.renderer, self.texture, null, null);
    _ = zsdl3.renderPresent(self.renderer);
}

const PaletteGuess = union(enum) {
    bg: u3,
    obj: u3,
};

fn guess_palettes(self: *TileWindow) [2][384]?PaletteGuess {
    // Initialize all 768 tiles across both banks as having no known palette
    var guesses: [2][384]?PaletteGuess = .{ .{null} ** 384, .{null} ** 384 };

    // 1. Scan the BG and Window Maps (0x9800 to 0x9FFF)
    for (0x9800..0xA000) |map_addr| {
        const addr: u16 = @intCast(map_addr);
        const tile_id = self.gbc.ppu.read_vram(0, addr);
        const attr = self.gbc.ppu.read_vram(1, addr);

        const cgb_palette: u3 = @truncate(attr & 0x07);
        const vram_bank: u1 = @truncate((attr >> 3) & 0x01);

        // Determine actual tile index (0-383) based on LCDC addressing mode
        var actual_idx: usize = 0;
        if (self.gbc.ppu.lcdc.bg_window_tile_data_area == 1) {
            // 0x8000 addressing mode
            actual_idx = tile_id;
        } else {
            // 0x9000 addressing mode (signed)
            const signed_id: i8 = @bitCast(tile_id);
            actual_idx = @intCast(@as(i32, signed_id) + 256);
        }

        if (actual_idx < 384) {
            guesses[vram_bank][actual_idx] = .{ .bg = cgb_palette };
        }
    }

    // 2. Scan OAM (Sprites)
    // OAM contains 40 sprites, each taking 4 bytes
    for (0..40) |i| {
        const tile_id = self.gbc.ppu.OAM[i * 4 + 2];
        const attr_byte = self.gbc.ppu.OAM[i * 4 + 3];
        const vram_bank: u1 = @truncate((attr_byte >> 3) & 0x01);
        const cgb_palette: u3 = @truncate(attr_byte & 0x07);

        // Sprites always use 0x8000 addressing
        guesses[vram_bank][tile_id] = .{ .obj = cgb_palette };
    }

    return guesses;
}
