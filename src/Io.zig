const Io = @This();

const Bus = @import("Bus.zig");

IOPorts: [0x80]u8 = @splat(0), // I/O Ports from 0xFF00 to 0xFFFF
bus: *Bus, // reference to bus for interrupt requests

joyp_action: u8 = 0xF,
joyp_direction: u8 = 0xF,

const Interrupts = enum(u3) {
    vblank = 0,
    lcd = 1,
    timer = 2,
    serial = 3,
    joypad = 4,
};

const Key1 = packed struct {
    switch_armed: bool,
    _padding: u6,
    current_speed: bool,
};

pub fn init(bus: *Bus) Io {
    var io = Io{ .bus = bus };
    io.IOPorts[0] = 0xCF; // Initialize JOYP register
    return io;
}

pub fn read(self: *const Io, address: u16) u8 {
    // --------------------- USED IN BLARGG TESTING ---------------------
    if (address == 0xFF44) {
        return 0x90;
    }
    // ----------------------------------------------------------------------

    return switch (address) {
        0xFF00 => self.getJoyp(),
        0xFF04...0xFF07 => self.bus.timer.read(address),
        0xFF40 => @bitCast(self.bus.ppu.lcdc),
        0xFF41 => @bitCast(self.bus.ppu.stat),
        0xFF42 => self.bus.ppu.scy,
        0xFF43 => self.bus.ppu.scx,
        0xFF44 => self.bus.ppu.ly,
        0xFF45 => self.bus.ppu.lyc,
        0xFF4A => self.bus.ppu.wy,
        0xFF4B => self.bus.ppu.wx,
        0xFF4D => self.IOPorts[0x4D], // KEY1
        0xFF4F => self.bus.vbk,
        0xFF70 => self.bus.wbk,
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
        0xFF00 => self.setJoyp(value),
        0xFF04...0xFF07 => self.bus.timer.write(address, value),
        0xFF40 => self.bus.ppu.lcdc = @bitCast(value),
        0xFF41 => self.bus.ppu.stat = @bitCast(value),
        0xFF42 => self.bus.ppu.scy = value,
        0xFF43 => self.bus.ppu.scx = value,
        0xFF44 => {}, // LY is read-only
        0xFF45 => self.bus.ppu.lyc = value,
        0xFF4A => self.bus.ppu.wy = value,
        0xFF4B => self.bus.ppu.wx = value,
        0xFF4D => self.setKey1(value),
        0xFF4F => self.bus.vbk = @intCast(value & 0b1),
        0xFF70 => self.bus.wbk = @min(value & 0b111, 1),
        else => self.IOPorts[address - 0xFF00] = value,
    }
}

// Seperate getters and setters when reads/writes should not tick the timer

pub fn getIF(self: *const Io) u8 {
    return self.IOPorts[0x0F];
}

pub fn setIF(self: *Io, value: u8) void {
    self.IOPorts[0x0F] = value;
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
    self.IOPorts[0x4D] |= value & 0x1; // only write bit 0
}

pub fn requestInterrupt(self: *Io, interrupt: Interrupts) void {
    const interrupt_flag = self.IOPorts[0x0F];
    const new_flag = interrupt_flag | (@as(u8, 1) << @intFromEnum(interrupt));
    self.IOPorts[0x0F] = new_flag;
}

pub fn toggleSpeed(self: *Io) void {
    var key1 = self.getKey1();
    key1.current_speed = !key1.current_speed;
    key1.switch_armed = false;
    self.IOPorts[0x4D] = @bitCast(key1);
}
