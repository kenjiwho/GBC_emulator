const Fetcher = @This();

const Ppu = @import("Ppu.zig");

ppu: *Ppu, // reference to PPU for memory access

pub fn init(ppu: *Ppu) Fetcher {
    return Fetcher{ .ppu = ppu };
}

const std = @import("std");
/// Determines which background/window tile to fetch pixels from
pub fn getTile(self: *Fetcher) u8 {
    std.debug.print("{d}\n", .{self.ppu.lx});
    return 0;
}
