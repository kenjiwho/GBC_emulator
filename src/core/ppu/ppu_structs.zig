pub const Lcdc = packed struct {
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

pub const Stat = packed struct {
    ppu_mode: PpuMode = PpuMode.oam_scan, // 0-1
    lyc_eq_ly: bool = false, // 2
    mode0_interrupt: bool = false, // 3
    mode1_interrupt: bool = false, // 4
    mode2_interrupt: bool = false, // 5
    lyc_interrupt: bool = false, // 6
    _padding: u1 = 0,
};

pub const Pixel = struct {
    color_index: u2,
    palette: u3,
    background_priority: bool,
};

pub const OamAttributes = packed struct {
    cgb_palette: u3 = 0, // 0-2
    vram_bank: u1 = 0, // 3
    dmg_palette: u1 = 0, // 4
    x_flip: bool = false, // 5
    y_flip: bool = false, // 6
    priority: bool = false, // 7
};

pub const OamEntry = packed struct {
    y_position: u8 = 0, // byte 0
    x_position: u8 = 0, // byte 1
    tile_index: u8 = 0, // byte 2
    attributes: OamAttributes = OamAttributes{}, // byte 3
};

pub const Bgpi = packed struct {
    address: u6 = 0, // 0-5
    _padding: u1 = 0,
    auto_increment: bool = false, // 6
};

pub const Obpi = packed struct {
    address: u6 = 0, // 0-5
    _padding: u1 = 0,
    auto_increment: bool = false, // 6
};
