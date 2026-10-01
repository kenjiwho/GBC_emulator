//! debugger for the emulator (VRAM viewer, execution pausing, memory inspection)
const Debugger = @This();

const std = @import("std");
const zsdl3 = @import("zsdl3");
const Gbc = @import("../Gbc.zig");
const TextBox = @import("TextBox.zig");

const FONT_DATA: []const u8 = @embedFile("../assets/fonts/JetBrainsMonoNL-Regular.ttf");

gbc: *Gbc,

is_paused: bool = false,
step_requested: bool = false,

text_box: TextBox,
text_buffer: [4096]u8 = undefined,

pub fn init(gbc: *Gbc) Debugger {
    return Debugger{
        .gbc = gbc,
        .text_box = TextBox.init(10, 10, 620, 620),
    };
}

pub fn wait(self: *Debugger) void {
    const window = zsdl3.createWindow(
        "Debugger window",
        640,
        640,
        zsdl3.SDL_WINDOW_RESIZABLE,
    ) orelse return;
    defer zsdl3.destroyWindow(window);
    const debugger_window_id = zsdl3.getWindowID(window);

    const renderer = zsdl3.createRenderer(window, null) orelse return;
    defer zsdl3.destroyRenderer(renderer);

    // Load font
    if (!zsdl3.ttf.init()) {
        return;
    }
    defer zsdl3.ttf.quit();

    const font_io = zsdl3.ioFromConstMem(FONT_DATA.ptr, FONT_DATA.len);
    // surface.SDL_IOStream and filesystem.SDL_IOStream are the same so we @ptrCast
    const font = zsdl3.ttf.openFontIO(@ptrCast(font_io), true, 16.0) orelse return;
    defer zsdl3.ttf.closeFont(font);

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
                zsdl3.SDL_EVENT_MOUSE_WHEEL => self.text_box.handleWheelEvent(event.wheel.y, event.wheel.mouse_x, event.wheel.mouse_y),
                else => {},
            }
        }

        if (self.step_requested) {
            self.step_requested = false;
            std.debug.print("SINGLE STEP\n", .{});
            _ = self.gbc.single_step();
        }
        self.render(renderer, font);
    }
}

fn render(self: *Debugger, renderer: *zsdl3.SDL_Renderer, font: *zsdl3.ttf.TTF_Font) void {
    _ = zsdl3.renderClear(renderer);

    const debug_text = std.fmt.bufPrintZ(
        &self.text_buffer,
        "=== REGISTERS ===\n" ++
            "PC: {X:0>4}   SP: {X:0>4}\n" ++
            "AF: {X:0>4}   BC: {X:0>4}\n" ++
            "DE: {X:0>4}   HL: {X:0>4}\n\n" ++
            "=== CPU FLAGS ===\n" ++
            "Z: {}  N: {}  H: {}  C: {}\n\n" ++
            "=== MEMORY AT PC ===\n" ++
            "[{X:0>4}]: {X:0>2} {X:0>2} {X:0>2} {X:0>2}\n",
        .{
            self.gbc.cpu.regs.PC,
            self.gbc.cpu.regs.SP,
            self.gbc.cpu.regs.getAF(),
            self.gbc.cpu.regs.getBC(),
            self.gbc.cpu.regs.getDE(),
            self.gbc.cpu.regs.getHL(),
            @intFromBool(self.gbc.cpu.getFlag(.Z)),
            @intFromBool(self.gbc.cpu.getFlag(.N)),
            @intFromBool(self.gbc.cpu.getFlag(.H)),
            @intFromBool(self.gbc.cpu.getFlag(.C)),
            self.gbc.cpu.regs.PC,
            self.gbc.bus.read(self.gbc.cpu.regs.PC),
            self.gbc.bus.read(self.gbc.cpu.regs.PC +% 1),
            self.gbc.bus.read(self.gbc.cpu.regs.PC +% 2),
            self.gbc.bus.read(self.gbc.cpu.regs.PC +% 3),
        },
    ) catch "Buffer too small";

    self.text_box.text_data = debug_text;
    self.text_box.render(renderer, font);

    _ = zsdl3.renderPresent(renderer);
    self.gbc.render();
}

fn handle_key_events(self: *Debugger, key: u32) void {
    switch (key) {
        zsdl3.SDLK_SPACE => self.is_paused = false,
        zsdl3.SDLK_n => self.step_requested = true,
        else => {},
    }
}
