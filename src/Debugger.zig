//! debugger for the emulator (VRAM viewer, execution pausing, memory inspection)
const Debugger = @This();

const Gbc = @import("Gbc.zig");

gbc: *Gbc,

pub fn init(gbc: *Gbc) Debugger {
    return Debugger{ .gbc = gbc };
}
