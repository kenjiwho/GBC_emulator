//! implementation of no mbc
const Mbc1 = @This();

ROM_size: u21,
external_RAM_enabled: bool = false,

pub fn init(rom_size_code: u8) Mbc1 {
    const ROM_size: u21 = @as(u21, 0x8000) * (@as(u7, 1) << @intCast(rom_size_code));

    return Mbc1{ .ROM_size = ROM_size };
}

pub fn setROMBank(self: *Mbc1, value: u8) void {
    // do nothing, no banking
    _ = self;
    _ = value;
}

pub fn setSecondaryBank(self: *Mbc1, value: u8) void {
    // do nothing, no banking
    _ = self;
    _ = value;
}

pub fn setMode(self: *Mbc1, value: u8) void {
    // do nothing, no banking
    _ = self;
    _ = value;
}

/// Map address in 0x4000-0x7FFF to actual ROM address based on current bank
pub fn mapROMAddress(self: *const Mbc1, address: u16) u21 {
    // do nothing, no banking
    _ = self;
    return address;
}

pub fn mapRAMAddress(self: *const Mbc1, address: u16) u15 {
    // do nothing, no banking
    _ = self;
    return @intCast(address);
}

pub fn toggleExternalRAM(self: *Mbc1, value: u8) void {
    if ((value & 0x0F) == 0xA) {
        self.external_RAM_enabled = true;
    } else {
        self.external_RAM_enabled = false;
    }
}
