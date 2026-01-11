//! implementation of MBC1 (Memory Bank Controller)
const MBC1 = @This();

ROM_S_bank: u5 = 1,
secondary_bank: u2 = 0, // either upper bits of ROM bank or RAM bank
mode: bool = false, // behaviour of secondary bank: false = ROM banking mode, true = RAM banking mode
ROM_size: u21,
num_ROM_banks: u128,
num_bits_ROM_banks: u3,
ExternalRAM_enabled: bool = false,

// TODO: implement MBC1M support

pub fn init(rom_size_code: u8) MBC1 {
    const ROM_size: u21 = @as(u21, 0x8000) * (@as(u7, 1) << @intCast(rom_size_code));
    const num_ROM_banks: u128 = ROM_size / 0x4000;
    const num_bits_ROM_banks: u3 = @intFromFloat(@log2(@as(f32, @floatFromInt(num_ROM_banks))));

    return MBC1{
        .ROM_size = ROM_size,
        .num_ROM_banks = num_ROM_banks,
        .num_bits_ROM_banks = num_bits_ROM_banks,
    };
}

pub fn setROMBank(self: *MBC1, value: u8) void {
    var bank: u5 = @truncate(value);
    if (bank == 0) {
        bank = 1;
    }
    self.ROM_S_bank = bank;
}

pub fn setSecondaryBank(self: *MBC1, value: u8) void {
    self.secondary_bank = @truncate(value);
}

pub fn setMode(self: *MBC1, value: u8) void {
    self.mode = (value & 0x01) == 1;
}

/// Map address in 0x4000-0x7FFF to actual ROM address based on current bank
pub fn mapROMAddress(self: *const MBC1, address: u16) u21 {
    switch (address) {
        0x0000...0x3FFF => {
            var true_address: u21 = @as(u21, address);
            if (self.mode) {
                true_address += (@as(u21, self.secondary_bank) << 19);
            }

            return true_address % self.ROM_size;
        },
        0x4000...0x7FFF => {
            var true_bank: u7 = (@as(u7, self.secondary_bank) << 5) + self.ROM_S_bank;
            // bank number is masked to required number of bits
            if (self.num_bits_ROM_banks < 7) {
                true_bank = true_bank & ((@as(u7, 1) << self.num_bits_ROM_banks) - 1);
            }

            return ((address - 0x4000) + (@as(u21, true_bank) * 0x4000)) % self.ROM_size;
        },
        else => unreachable, // invalid address for ROM banking
    }
}

pub fn mapRAMAddress(self: *const MBC1, address: u16) u15 {
    var ram_bank: u2 = 0;
    if (self.mode) {
        ram_bank = self.secondary_bank;
    }

    return @intCast(((address - 0xA000) + (@as(u15, ram_bank) * 0x2000)) % 0x8000);
}

pub fn toggleExternalRAM(self: *MBC1, value: u8) void {
    if ((value & 0x0F) == 0xA) {
        self.ExternalRAM_enabled = true;
    } else {
        self.ExternalRAM_enabled = false;
    }
}
