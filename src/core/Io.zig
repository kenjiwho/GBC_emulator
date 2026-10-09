const Io = @This();

const Bus = @import("Bus.zig");

IOPorts: [0x80]u8 = @splat(0), // I/O Ports from 0xFF00 to 0xFFFF
bus: *Bus, // reference to bus for interrupt requests

joyp_action: u8 = 0xF,
joyp_direction: u8 = 0xF,

const Interrupts = enum(u3) {
    vblank = 0,
    stat = 1,
    timer = 2,
    serial = 3,
    joypad = 4,
};

const Key1 = packed struct {
    switch_armed: bool,
    _padding: u6,
    is_double_speed: bool, // 0 = normal speed, 1 = double speed
};

pub fn init(bus: *Bus) Io {
    var io = Io{ .bus = bus };
    io.IOPorts[0] = 0xCF; // Initialize JOYP register
    return io;
}

pub fn read(self: *const Io, address: u16) u8 {
    return switch (address) {
        0xFF00 => self.getJoyp(), // Joypad input
        0xFF01...0xFF02 => self.IOPorts[address - 0xFF00], // TODO: implement Serial transfer
        0xFF04...0xFF07 => self.bus.timer.read(address), // Timer and divider
        0xFF0F => self.getIF(), // Interrupts
        0xFF10...0xFF26 => self.IOPorts[address - 0xFF00], // TODO: implement Audio
        0xFF30...0xFF3F => self.IOPorts[address - 0xFF00], // TODO: implement Wave pattern
        0xFF40...0xFF4B => self.bus.ppu.read(address), // LCD Control, Status, Position, Scrolling, and Palettes
        0xFF4C => self.IOPorts[0x4C], // TODO: implement KEY0
        0xFF4D => self.IOPorts[0x4D], // KEY1
        0xFF4F => @as(u8, self.bus.vbk) | 0xFE, // VRAM Bank Select (bit 0) + unused bits read as 1
        0xFF50 => @as(u8, self.bus.wbk) | 0xF8, // TODO: implement Boot ROM mapping control
        0xFF51...0xFF55 => self.IOPorts[address - 0xFF00], // TODO: implement VRAM DMA
        0xFF56 => self.IOPorts[address - 0xFF00], // TODO: implement IR port
        0xFF68...0xFF6B => self.bus.ppu.read(address), // BG / OBJ Palettes
        0xFF6C => self.IOPorts[0x6C], // TODO: implement Object priority mode
        0xFF70 => self.bus.wbk, // WRAM Bank Select
        else => self.IOPorts[address - 0xFF00],
    };
}

const std = @import("std");
pub fn write(self: *Io, address: u16, value: u8) void {
    // --------------------- USED IN BLARGG TESTING ---------------------
    // Handle blargg test output to serial port
    if (address == 0xFF02 and value == 0x81) {
        const byte = self.IOPorts[0x01];
        std.debug.print("{c}", .{byte});
    }
    // ----------------------------------------------------------------------

    switch (address) {
        0xFF00 => self.setJoyp(value), // Joypad input
        0xFF01...0xFF02 => {}, // TODO: implement Serial transfer
        0xFF04...0xFF07 => self.bus.timer.write(address, value), // Timer and divider
        0xFF0F => self.setIF(value), // Interrupts
        0xFF10...0xFF26 => {}, // TODO: implement Audio
        0xFF30...0xFF3F => {}, // TODO: implement Wave pattern
        0xFF40...0xFF4B => self.bus.ppu.write(address, value), // LCD Control, Status, Position, Scrolling, and Palettes
        0xFF4C => {}, // TODO: implement KEY0
        0xFF4D => self.setKey1(value), // KEY1
        0xFF4F => self.bus.vbk = @intCast(value & 0b1), // VRAM Bank Select
        0xFF50 => {
            self.bus.boot_rom_enabled = false;
        }, // Boot ROM mapping control
        0xFF51...0xFF55 => {}, // TODO: implement VRAM DMA
        0xFF56 => {}, // TODO: IR port
        0xFF68...0xFF6B => self.bus.ppu.write(address, value), // BG / OBJ Palettes
        0xFF6C => {}, // TODO: implement Object priority mode
        0xFF70 => self.bus.wbk = @min(value & 0b111, 1), // WRAM Bank Select
        else => self.IOPorts[address - 0xFF00] = value,
    }
}

// Seperate getters and setters when reads/writes should not tick the timer

pub fn getIF(self: *const Io) u8 {
    return self.IOPorts[0x0F] | 0xE0; // unused bits read as 1
}

pub fn setIF(self: *Io, value: u8) void {
    self.IOPorts[0x0F] = value & 0x1F;
}

pub fn getJoyp(self: *const Io) u8 {
    var joyp = self.IOPorts[0x00];
    if ((joyp & 0x10) == 0) {
        joyp &= (self.joyp_direction | 0xF0);
    }
    if ((joyp & 0x20) == 0) {
        joyp &= (self.joyp_action | 0xF0);
    }
    return joyp;
}

fn setJoyp(self: *Io, value: u8) void {
    self.IOPorts[0x00] = (self.IOPorts[0x00] & 0xCF) | (value & 0x30);
}

pub fn getKey1(self: *const Io) Key1 {
    return @bitCast(self.IOPorts[0x4D]);
}

fn setKey1(self: *Io, value: u8) void {
    self.IOPorts[0x4D] = (self.IOPorts[0x4D] & 0xFE) | (value & 0x1); // only write bit 0
}

pub fn request_interrupt(self: *Io, interrupt: Interrupts) void {
    const interrupt_flag = self.IOPorts[0x0F];
    const new_flag = interrupt_flag | (@as(u8, 1) << @intFromEnum(interrupt));
    self.IOPorts[0x0F] = new_flag;
}

pub fn toggleSpeed(self: *Io) void {
    var key1 = self.getKey1();
    key1.is_double_speed = !key1.is_double_speed;
    key1.switch_armed = false;
    self.IOPorts[0x4D] = @bitCast(key1);
}
