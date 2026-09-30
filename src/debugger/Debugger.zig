//! debugger for the emulator (VRAM viewer, execution pausing, memory inspection)
const Debugger = @This();

const std = @import("std");
const zsdl3 = @import("zsdl3");
const Gbc = @import("../Gbc.zig");

gbc: *Gbc,
is_paused: bool = false,
step_requested: bool = false,

pub fn init(gbc: *Gbc) Debugger {
    return Debugger{ .gbc = gbc };
}

pub fn wait(self: *Debugger) void {
    const window = zsdl3.createWindow(
        "Debugger window",
        1080,
        720,
        zsdl3.SDL_WINDOW_RESIZABLE,
    ) orelse return;
    defer zsdl3.destroyWindow(window);
    const debugger_window_id = zsdl3.getWindowID(window);

    const renderer = zsdl3.createRenderer(window, null) orelse return;
    defer zsdl3.destroyRenderer(renderer);

    while (self.is_paused) {
        var event: zsdl3.SDL_Event = undefined;
        while (zsdl3.pollEvent(&event)) {
            switch (event.type) {
                zsdl3.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    // Close the window if it's the debugger window, otherwise quit the GBC
                    if (event.window.windowID == debugger_window_id) {
                        self.is_paused = false;
                    } else {
                        self.is_paused = false;
                        // push a quit event to the event queue for the GBC event handler to pick up
                        var quit_event = std.mem.zeroes(zsdl3.SDL_Event);
                        quit_event.type = zsdl3.SDL_EVENT_QUIT;
                        _ = zsdl3.pushEvent(&quit_event);
                        return;
                    }
                    return;
                },
                zsdl3.SDL_EVENT_KEY_DOWN => self.handle_key_events(event.key.key),
                else => {},
            }
        }

        if (self.step_requested) {
            self.step_requested = false;
            std.debug.print("SINGLE STEP\n", .{});
            _ = self.gbc.single_step();
        }
        self.gbc.render();
    }
}

fn handle_key_events(self: *Debugger, key: u32) void {
    switch (key) {
        zsdl3.SDLK_SPACE => self.is_paused = false,
        zsdl3.SDLK_n => self.step_requested = true,
        else => {},
    }
}
