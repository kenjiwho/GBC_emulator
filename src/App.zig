const App = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zsdl3 = @import("zsdl3");
const Gbc = @import("core/Gbc.zig");
const WindowManager = @import("gui/WindowManager.zig");

const CPU_CLOCK_HZ = 4_194_304;
const CYCLES_PER_FRAME = 70_224;
const NS_PER_FRAME: f64 = @as(f64, CYCLES_PER_FRAME) * 1_000_000_000 / CPU_CLOCK_HZ;

gbc: *Gbc,
window_manager: WindowManager,

quit: bool = false,

pub fn init(io: Io, allocator: Allocator) !App {
    const gbc = try Gbc.init(
        io,
        allocator,
        "./tests/cgb-acid2.gbc",
        "./tests/gbc_bios.bin",
    );

    return App{
        .gbc = gbc,
        .window_manager = try WindowManager.init(gbc),
    };
}

pub fn deinit(self: *App, allocator: Allocator) void {
    self.gbc.deinit(allocator);
    self.window_manager.deinit();
}

/// Main loop
pub fn run(self: *App) !void {
    var last_time = zsdl3.getTicksNS();
    var accumulator: f64 = 0; // accumulator for frame timing
    while (!self.quit) {
        self.quit = self.window_manager.process_events();

        const current_time = zsdl3.getTicksNS();
        var delta: f64 = @floatFromInt(current_time - last_time);
        // clamp delta to avoid the emulator trying to catch up when the window was paused
        if (delta >= 100_000_000) delta = NS_PER_FRAME;
        accumulator += delta;
        last_time = current_time;

        while (accumulator >= NS_PER_FRAME) : (accumulator -= NS_PER_FRAME) {
            self.gbc.step_frame();
        }
        self.window_manager.render();

        // if the accumulator doesn't have enough time to trigger the next frame yet
        // calculate how many nanoseconds to wait
        if (accumulator < NS_PER_FRAME) {
            const sleep_ns: u64 = @intFromFloat(NS_PER_FRAME - accumulator);
            zsdl3.delay(@intCast(sleep_ns / 1_000_000));
        }
    }
}
