//! Window manager for the emulator
const WindowManager = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const zsdl3 = @import("zsdl3");
const MainWindow = @import("MainWindow.zig");
const CpuWindow = @import("CpuWindow.zig");
const Gbc = @import("../core/Gbc.zig");

const FONT_DATA: []const u8 = @embedFile("../assets/fonts/JetBrainsMonoNL-Regular.ttf");

const Window = union(enum) {
    main: MainWindow,

    pub fn deinit(self: *const Window) void {
        switch (self.*) {
            inline else => |*w| w.deinit(),
        }
    }

    pub fn get_id(self: *const Window) u32 {
        return switch (self.*) {
            inline else => |*w| w.get_id(),
        };
    }

    pub fn handle_event(self: *Window, event: zsdl3.SDL_Event) void {
        switch (self.*) {
            inline else => |*w| w.handle_event(event),
        }
    }

    pub fn render(self: *const Window) void {
        switch (self.*) {
            inline else => |*w| w.render(),
        }
    }
};

gbc: *Gbc,
windows: ArrayList(Window),
font: *zsdl3.ttf.TTF_Font,

pub fn init(allocator: Allocator, gbc: *Gbc) !WindowManager {
    if (!zsdl3.init(zsdl3.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }
    if (!zsdl3.ttf.init()) {
        return error.TTFInitFailed;
    }

    const font_io = zsdl3.ioFromConstMem(FONT_DATA.ptr, FONT_DATA.len) orelse return error.FontIoFailed;
    // surface.SDL_IOStream and filesystem.SDL_IOStream are the same so we @ptrCast
    const font = zsdl3.ttf.openFontIO(@ptrCast(font_io), true, 16.0) orelse return error.FontFailed;

    var windows: ArrayList(Window) = .empty;

    try windows.append(allocator, .{ .main = try MainWindow.init(&gbc.ppu.screen) });

    return WindowManager{
        .gbc = gbc,
        .windows = windows,
        .font = font,
    };
}

pub fn deinit(self: *WindowManager, allocator: Allocator) void {
    for (self.windows.items) |window| {
        window.deinit();
    }
    self.windows.deinit(allocator);
    zsdl3.ttf.closeFont(self.font);
    zsdl3.ttf.quit();
    zsdl3.quit();
}

/// render all windows
pub fn render_all(self: *const WindowManager) void {
    for (self.windows.items) |window| {
        window.render();
    }
}

/// route events to the correct window
pub fn process_events(self: *const WindowManager) bool {
    var event: zsdl3.SDL_Event = undefined;
    while (zsdl3.pollEvent(&event)) {
        if (event.type == zsdl3.SDL_EVENT_QUIT) return true;

        const target_id = event.window.windowID;

        for (self.windows.items) |*window| {
            if (target_id == window.get_id()) {
                window.handle_event(event);
                break;
            }
        }
    }
    return false;
}
