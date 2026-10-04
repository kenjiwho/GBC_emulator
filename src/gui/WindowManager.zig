//! Window manager for the emulator
const WindowManager = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const zsdl3 = @import("zsdl3");
const MainWindow = @import("MainWindow.zig");
const CpuWindow = @import("CpuWindow.zig");
const TileWindow = @import("TileWindow.zig");
const Gbc = @import("../core/Gbc.zig");

const FONT_DATA: []const u8 = @embedFile("../assets/fonts/JetBrainsMonoNL-Regular.ttf");

// actions that the WindowManager can request from App
pub const AppActions = struct {
    quit: bool = false,
    toggle_debug: bool = false,
    single_step: bool = false,

    pub fn merge(self: *AppActions, other: AppActions) void {
        self.quit = self.quit or other.quit;
        self.toggle_debug = self.toggle_debug or other.toggle_debug;
        self.single_step = self.single_step or other.single_step;
    }
};

const Window = union(enum) {
    main: MainWindow,
    cpu: CpuWindow,
    tile: TileWindow,

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
                actions.merge(win_actions);
                break;
            }
        }
    }
    return actions;
}

pub fn toggle_debug(self: *WindowManager, gpa: Allocator) !void {
    self.debug_mode = !self.debug_mode;

    if (self.debug_mode) {
        // create debug windows
        const cpu_window = try CpuWindow.init(self.gbc, self.font);
        const tile_window = try TileWindow.init(self.gbc);
        try self.windows.append(gpa, .{ .cpu = cpu_window });
        try self.windows.append(gpa, .{ .tile = tile_window });
    } else {
        // destroy debug windows
        var i: usize = 0;
        while (i < self.windows.items.len) {
            switch (self.windows.items[i]) {
                .cpu => |*cpu_win| {
                    cpu_win.deinit();
                    _ = self.windows.swapRemove(i);
                },
                .tile => |*tile_win| {
                    tile_win.deinit();
                    _ = self.windows.swapRemove(i);
                },
                else => i += 1,
            }
        }
    }
}
