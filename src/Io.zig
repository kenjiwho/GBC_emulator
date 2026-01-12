const Io = @This();

const Bus = @import("Bus.zig");

IOPorts: [0x80]u8 = @splat(0), // I/O Ports from 0xFF00 to 0xFFFF
bus: *Bus, // reference to bus for interrupt requests

joyp_action: u8 = 0xF,
joyp_direction: u8 = 0xF,

const interrupts = enum(u3) {
    VBlank = 0,
    LCD = 1,
    Timer = 2,
    Serial = 3,
    Joypad = 4,
};

pub fn init(bus: *Bus) Io {
    var io = Io{ .bus = bus };
    io.IOPorts[0] = 0xCF; // Initialize JOYP register
    return io;
}

pub fn read(self: *const Io, address: u16) u8 {
    // --------------------- USED IN BLARGG TESTING ---------------------
    // Handle blargg test output to serial port
    if (address == 0xFF44) {
        return 0x90;
    }
    // ----------------------------------------------------------------------

    return switch (address) {
        0xFF00 => self.getJoyp(),
        0xFF04...0xFF07 => self.bus.timer.read(address),
        0xFF4D => self.getKey1(),
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
        0xFF4D => self.setKey1(value),
        else => self.IOPorts[address - 0xFF00] = value,
    }
}

/// Seperate getters and setters when reads/writes should not tick the timer
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

pub fn getKey1(self: *const Io) u8 {
    return self.IOPorts[0x4D];
}

fn setKey1(self: *Io, value: u8) void {
    self.IOPorts[0x4D] = (self.IOPorts[0x4D] & 0x80) | (value & 0x01);
}

pub fn requestInterrupt(self: *Io, interrupt: interrupts) void {
    const interrupt_flag = self.IOPorts[0x0F];
    const new_flag = interrupt_flag | (@as(u8, 1) << @intFromEnum(interrupt));
    self.IOPorts[0x0F] = new_flag;
}

pub fn toggleSpeed(self: *Io) void {
    var key1 = self.getKey1();
    key1 ^= 0x80;
    key1 &= 0x80;
    self.setKey1(key1);
}
