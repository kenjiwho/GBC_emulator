//! Memory Bank Controller (MBC) abstraction
const MBC1 = @import("mbc/MBC1.zig");

pub const MBC = union(enum) {
    MBC1: MBC1,

    pub fn init(cartridge_type: u8, rom_size_code: u8) MBC {
        switch (cartridge_type) {
            0x01...0x03 => {
                return MBC{ .MBC1 = MBC1.init(rom_size_code) };
            },
            else => @panic("Unsupported cartridge type"),
        }
    }

    pub fn setROMBank(self: *MBC, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.setROMBank(value),
        }
    }

    pub fn setSecondaryBank(self: *MBC, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.setSecondaryBank(value),
        }
    }

    pub fn setMode(self: *MBC, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.setMode(value),
        }
    }

    pub fn mapROMAddress(self: *const MBC, address: u16) u21 {
        return switch (self.*) {
            inline else => |*mbc| mbc.mapROMAddress(address),
        };
    }

    pub fn mapRAMAddress(self: *const MBC, address: u16) u15 {
        return switch (self.*) {
            inline else => |*mbc| mbc.mapRAMAddress(address),
        };
    }

    pub fn toggleExternalRAM(self: *MBC, value: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.toggleExternalRAM(value),
        }
    }

    pub fn ExternalRAM_enabled(self: *const MBC) bool {
        return switch (self.*) {
            inline else => |*mbc| mbc.ExternalRAM_enabled,
        };
    }
};
