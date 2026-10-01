const App = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Gbc = @import("core/Gbc.zig");
const WindowManager = @import("gui/WindowManager.zig");

gbc: *Gbc,
window_manager: WindowManager,

pub fn init(io: Io, allocator: Allocator) !App {
    const gbc = try Gbc.init(
        io,
        allocator,
        "./tests/cgb-acid2.gbc",
        "./tests/gbc_bios.bin",
    );

    return App{
        .gbc = gbc,
        .window_manager = WindowManager.init(),
    };
}

pub fn deinit(self: *App, allocator: Allocator) void {
    self.gbc.deinit(allocator);
}

pub fn run(self: *App) !void {
    try self.gbc.run();
}
