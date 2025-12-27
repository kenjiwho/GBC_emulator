const Registers = @This();

// AF
A: u8 = 0, // Accumulator
F: u8 = 0, // Flags
// BC
B: u8 = 0,
C: u8 = 0,
// DE
D: u8 = 0,
E: u8 = 0,
// HL
H: u8 = 0,
L: u8 = 0,
SP: u16 = 0, // Stack Pointer
PC: u16 = 0, // Program Counter

pub const Flag = enum(u3) {
    Z = 7, // Zero Flag
    N = 6, // Subtract Flag
    H = 5, // Half Carry Flag
    C = 4, // Carry Flag
};

pub fn init() Registers {
    return Registers{};
}

/// Gets flag from flags register
pub fn getFlag(self: *Registers, flag: Flag) bool {
    const bit: u3 = @intFromEnum(flag);

    return ((self.F >> bit) & 0b1) == 1;
}

/// Sets the flags register
pub fn setFlag(self: *Registers, flag: Flag, value: bool) void {
    const bit: u3 = @intFromEnum(flag);

    if (value) {
        self.F |= @as(u8, 1) << bit;
    } else {
        self.F &= ~(@as(u8, 1) << bit);
    }
}

/// Gets the value of an 8-bit register
pub fn getR8(self: *Registers, r8: u8) u8 {
    return switch (r8) {
        0 => self.B,
        1 => self.C,
        2 => self.D,
        3 => self.E,
        4 => self.H,
        5 => self.L,
        6 => unreachable, // (HL) not a register
        7 => self.A,
        else => unreachable,
    };
}

/// Sets the value of an 8-bit register
pub fn setR8(self: *Registers, r8: u8, value: u8) void {
    switch (r8) {
        0 => self.B = value,
        1 => self.C = value,
        2 => self.D = value,
        3 => self.E = value,
        4 => self.H = value,
        5 => self.L = value,
        6 => unreachable, // (HL) not a register
        7 => self.A = value,
        else => unreachable,
    }
}

/// Gets the value of a 16-bit register pair
pub fn getR16(self: *Registers, r16: u8) u16 {
    return switch (r16) {
        0 => (@as(u16, self.B) << 8) | self.C,
        1 => (@as(u16, self.D) << 8) | self.E,
        2 => (@as(u16, self.H) << 8) | self.L,
        3 => self.SP,
        else => unreachable,
    };
}

/// Sets the value of a 16-bit register pair
pub fn setR16(self: *Registers, r16: u8, value: u16) void {
    switch (r16) {
        0 => {
            self.B = @intCast(value >> 8);
            self.C = @intCast(value & 0xFF);
        },
        1 => {
            self.D = @intCast(value >> 8);
            self.E = @intCast(value & 0xFF);
        },
        2 => {
            self.H = @intCast(value >> 8);
            self.L = @intCast(value & 0xFF);
        },
        3 => {
            self.SP = value;
        },
        else => unreachable,
    }
}

/// Gets the address pointed to by a 16-bit register pair, with optional
/// increment/decrement for HL.
pub fn getR16mem(self: *Registers, r16mem: u8) u16 {
    return switch (r16mem) {
        0 => (@as(u16, self.B) << 8) | self.C, // BC
        1 => (@as(u16, self.D) << 8) | self.E, // DE
        2 => { // HLI
            const addr = (@as(u16, self.H) << 8) | self.L;
            self.L, const overflow: u1 = @addWithOverflow(self.L, 1);
            self.H +%= overflow;
            return addr;
        },
        3 => { // HLD
            const addr = (@as(u16, self.H) << 8) | self.L;
            self.L, const underflow: u1 = @subWithOverflow(self.L, 1);
            self.H -%= underflow;
            return addr;
        },
        else => unreachable,
    };
}
