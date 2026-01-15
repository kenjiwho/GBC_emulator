//! Memory Bank Controller (MBC) abstraction
const Mbc1 = @import("Mbc1.zig");

pub const Mbc = union(enum) {
    Mbc1: Mbc1,

    pub fn init(cartridge_type: u8, rom_size_code: u8) Mbc {
        switch (cartridge_type) {
            0x01...0x03 => {
                return Mbc{ .Mbc1 = Mbc1.init(rom_size_code) };
            },
            else => @panic("Unsupported cartridge type"),
        }
    }

    pub fn setROMBank(self: *Mbc, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.setROMBank(value),
        }
    }

    pub fn setSecondaryBank(self: *Mbc, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.setSecondaryBank(value),
        }
    }

    pub fn setMode(self: *Mbc, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.setMode(value),
        }
    }

    pub fn mapROMAddress(self: *const Mbc, address: u16) u21 {
        return switch (self.*) {
            inline else => |*mbc| mbc.mapROMAddress(address),
        };
    }

    pub fn mapRAMAddress(self: *const Mbc, address: u16) u15 {
        return switch (self.*) {
            inline else => |*mbc| mbc.mapRAMAddress(address),
        };
    }

    pub fn toggleExternalRAM(self: *Mbc, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.toggleExternalRAM(value),
        }
    }

    pub fn ExternalRAM_enabled(self: *const Mbc) bool {
        return switch (self.*) {
            inline else => |*mbc| mbc.external_RAM_enabled,
        };
    }
};
