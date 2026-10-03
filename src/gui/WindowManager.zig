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

// actions that the WindowManager can request from App
pub const AppActions = struct {
    quit: bool = false,
    toggle_debug: bool = false,
    single_step: bool = false,
};

const Window = union(enum) {
    main: MainWindow,
    cpu: CpuWindow,

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

    pub fn handle_event(self: *Window, event: zsdl3.SDL_Event) AppActions {
        return switch (self.*) {
            inline else => |*w| w.handle_event(event),
        };
    }

    pub fn render(self: *Window) void {
        switch (self.*) {
            inline else => |*w| w.render(),
        }
    }
};

gbc: *Gbc,
windows: ArrayList(Window),
font: *zsdl3.ttf.TTF_Font,
debug_mode: bool = false,

pub fn init(gpa: Allocator, gbc: *Gbc) !WindowManager {
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

    try windows.append(gpa, .{ .main = try MainWindow.init(&gbc.ppu.screen) });

    return WindowManager{
        .gbc = gbc,
        .windows = windows,
        .font = font,
    };
}

pub fn deinit(self: *WindowManager, gpa: Allocator) void {
    for (self.windows.items) |win| {
        win.deinit();
    }
    self.windows.deinit(gpa);
    zsdl3.ttf.closeFont(self.font);
    zsdl3.ttf.quit();
    zsdl3.quit();
}

/// render all windows
pub fn render_all(self: *const WindowManager) void {
    for (self.windows.items) |*win| {
        win.render();
    }
}

/// route events to the correct window
pub fn process_events(self: *WindowManager) AppActions {
    var actions = AppActions{};

    var event: zsdl3.SDL_Event = undefined;
    while (zsdl3.pollEvent(&event)) {
        if (event.type == zsdl3.SDL_EVENT_QUIT) actions.quit = true;

        const target_id = event.window.windowID;
        for (self.windows.items) |*win| {
            if (target_id == win.get_id()) {
                const win_actions = win.handle_event(event);
                actions.quit |= win_actions.quit;
                actions.toggle_debug |= win_actions.toggle_debug;
                actions.single_step |= win_actions.single_step;
                break;
            }
        }
    }
    return actions;
}

pub fn toggle_debug(self: *WindowManager, gpa: Allocator) !void {
    self.debug_mode = !self.debug_mode;

    if (self.debug_mode) {
        const cpu_window = try CpuWindow.init(self.gbc, self.font);
        try self.windows.append(gpa, .{ .cpu = cpu_window });
    } else {
        for (0.., self.windows.items) |i, win| {
            switch (win) {
                .cpu => |*cpu_win| {
                    cpu_win.deinit();
                    _ = self.windows.swapRemove(i);
                },
                else => {},
            }
        }
    }
}
