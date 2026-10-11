//! implementation of MBC1 (Memory Bank Controller)
const Mbc1 = @This();

ROM_bank: u5 = 1,
secondary_bank: u2 = 0, // either upper bits of ROM bank or RAM bank
mode: bool = false, // behaviour of secondary bank: false = ROM banking mode, true = RAM banking mode
external_ROM_start_address: u16 = 0x4000,
max_ROM_size: u21,
num_ROM_banks: u21,
num_bits_ROM_banks: u3,
external_RAM_enabled: bool = false,
external_RAM_start_address: u16 = 0xA000,
max_RAM_size: u16 = 0x8000,

// TODO: implement MBC1M support

pub fn init(rom_size_code: u8) Mbc1 {
    const ROM_size: u21 = @as(u21, 0x8000) * (@as(u7, 1) << @intCast(rom_size_code));
    // >> 14 to get number of 16KB banks
    const num_ROM_banks: u21 = ROM_size >> 14;
    const num_bits_ROM_banks: u3 = @intFromFloat(@log2(@as(f32, @floatFromInt(num_ROM_banks))));

    return Mbc1{
        .max_ROM_size = ROM_size,
        .num_ROM_banks = num_ROM_banks,
        .num_bits_ROM_banks = num_bits_ROM_banks,
    };
}

pub fn setROMBank(self: *Mbc1, value: u8) void {
    self.ROM_bank = @truncate(value);
}

pub fn setSecondaryBank(self: *Mbc1, value: u8) void {
    self.secondary_bank = @truncate(value);
}

pub fn setMode(self: *Mbc1, value: u8) void {
    self.mode = (value & 0x01) == 1;
}

/// Map address in 0x4000-0x7FFF to actual ROM address based on current bank
pub fn mapROMAddress(self: *const Mbc1, address: u16) u21 {
    switch (address) {
        0x4000...0x7FFF => {
            var true_bank: u7 = (@as(u7, self.secondary_bank) << 5) + @max(self.ROM_bank, 1);
            // bank number is masked to required number of bits
            if (self.num_bits_ROM_banks < 7) {
                true_bank = true_bank & ((@as(u7, 1) << self.num_bits_ROM_banks) - 1);
            }

            // << 14 is a faster equivalent to * 0x4000
            return ((address - self.external_ROM_start_address) + (@as(u21, true_bank) << 14)) % self.max_ROM_size;
        },
        else => unreachable, // invalid address for ROM banking
    }
}

pub fn mapRAMAddress(self: *const Mbc1, address: u16) u15 {
    var ram_bank: u2 = 0;
    if (self.mode) {
        ram_bank = self.secondary_bank;
    }

    // << 13 is a faster equivalent to * 0x2000
    return @intCast(((address - self.external_RAM_start_address) + (@as(u15, ram_bank) << 13)) % self.max_RAM_size);
}

pub fn toggleExternalRAM(self: *Mbc1, value: u8) void {
    if ((value & 0x0F) == 0xA) {
        self.external_RAM_enabled = true;
    } else {
        self.external_RAM_enabled = false;
    }
}
