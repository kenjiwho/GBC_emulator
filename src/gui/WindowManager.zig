//! Window manager for the emulator
const WindowManager = @This();

const std = @import("std");
const zsdl3 = @import("zsdl3");
const MainWindow = @import("MainWindow.zig");
const Gbc = @import("../core/Gbc.zig");

gbc: *Gbc,
main_window: MainWindow,

pub fn init(gbc: *Gbc) !WindowManager {
    if (!zsdl3.init(zsdl3.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }

    return WindowManager{
        .gbc = gbc,
        .main_window = try MainWindow.init(
            &gbc.ppu.screen,
        ),
    };
}

pub fn deinit(self: *WindowManager) void {
    self.main_window.deinit();
    zsdl3.quit();
}

pub fn render(self: *WindowManager) void {
    self.main_window.render();
}

pub fn process_events(self: *WindowManager) bool {
    var event: zsdl3.SDL_Event = undefined;
    while (zsdl3.pollEvent(&event)) {
        switch (event.type) {
            zsdl3.SDL_EVENT_QUIT => return true,
            zsdl3.SDL_EVENT_KEY_DOWN => self.process_key_events(event.key.key),
            else => {},
        }
    }
    return false;
}

fn process_key_events(self: *WindowManager, key: u32) void {
    _ = self;
    switch (key) {
        // zsdl3.SDLK_SPACE => self.debugger.is_paused = true,
        else => {},
    }
}
