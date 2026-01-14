const Ppu = @This();

const rl = @cImport({
    @cInclude("raylib.h");
});
const Bus = @import("Bus.zig");

pub const SCREEN_HEIGHT: f32 = 144;
pub const SCREEN_WIDTH: f32 = 160;

screen: [SCREEN_HEIGHT * SCREEN_WIDTH]rl.Color = @splat(rl.BLACK), // 144x160 pixels
bus: *Bus, // reference to the bus for memory-mapped I/O

pub fn init(bus: *Bus) Ppu {
    return Ppu{ .bus = bus };
}

const std = @import("std");
pub fn step(self: *Ppu, dots: usize) void {
    _ = self;
    // PPU step logic goes here
    std.debug.print("{d}\n", .{dots});
}
