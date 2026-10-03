//! debugger for the emulator (VRAM viewer, execution pausing, memory inspection)
const Debugger = @This();

const std = @import("std");
const zsdl3 = @import("zsdl3");
const Gbc = @import("../Gbc.zig");
const TextBox = @import("../../gui/widgets/TextBox.zig");

const FONT_DATA: []const u8 = @embedFile("../../assets/fonts/JetBrainsMonoNL-Regular.ttf");
const MS_PER_FRAME = 1000.0 / 60.0; // 60 FPS

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
        const frame_start = zsdl3.getTicks();

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
                zsdl3.SDL_EVENT_WINDOW_RESIZED => {
                    self.text_box.resize(event.window.data1 - 20, event.window.data2 - 20);
                },
                else => {},
            }
        }

        if (self.step_requested) {
            self.step_requested = false;
            _ = self.gbc.single_step();
        }
        self.render(renderer, font);

        // limit frame rate to 60 FPS
        const frame_end = zsdl3.getTicks();
        const frame_time = frame_end - frame_start;

        if (@as(f32, @floatFromInt(frame_time)) < MS_PER_FRAME) {
            const sleep_ms: u64 = @intFromFloat(MS_PER_FRAME - @as(f32, @floatFromInt(frame_time)));
            zsdl3.delay(@intCast(sleep_ms));
        }
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
            self.debug_read(self.gbc.cpu.regs.PC),
            self.debug_read(self.gbc.cpu.regs.PC +% 1),
            self.debug_read(self.gbc.cpu.regs.PC +% 2),
            self.debug_read(self.gbc.cpu.regs.PC +% 3),
        },
    ) catch "Buffer too small";

    self.text_box.text_data = debug_text;
    self.text_box.render(renderer, font);

    _ = zsdl3.renderPresent(renderer);
    // self.gbc.render();
}

fn handle_key_events(self: *Debugger, key: u32) void {
    switch (key) {
        zsdl3.SDLK_SPACE => self.is_paused = false,
        zsdl3.SDLK_n => self.step_requested = true,
        else => {},
    }
}

pub fn debug_read(self: *Debugger, address: u16) u8 {
    if (self.gbc.bus.boot_rom_enabled) {
        if (address <= 0x00FF) {
            return self.gbc.bus.boot_ROM[address]; // First 256 bytes
        } else if (address >= 0x0100 and address <= 0x014F) {
            return self.gbc.bus.ROM[address]; // Read from the game cartridge header
        } else if (address >= 0x0200 and address <= 0x08FF) {
            return self.gbc.bus.boot_ROM[address]; // second mapped region of CGB boot ROM
        }
    }

    return switch (address) {
        0x0000...0x3FFF => self.gbc.bus.ROM[address],
        0x4000...0x7FFF => self.gbc.bus.ROM[self.gbc.bus.mbc.mapROMAddress(address)],
        0x8000...0x9FFF => self.gbc.bus.ppu.read_vram_cpu(self.gbc.bus.vbk, address),
        0xA000...0xBFFF => if (self.gbc.bus.mbc.ExternalRAM_enabled()) self.gbc.bus.external_RAM[address - 0xA000] else 0xFF,
        0xC000...0xCFFF => self.gbc.bus.WRAM[address - 0xC000],
        0xD000...0xDFFF => self.gbc.bus.WRAM[(address - 0xD000) + (@as(u16, self.gbc.bus.wbk) * 0x1000)],
        0xE000...0xEFFF => self.gbc.bus.WRAM[address - 0xE000], // Echo RAM
        0xF000...0xFDFF => self.gbc.bus.WRAM[(address - 0xF000) + (@as(u16, self.gbc.bus.wbk) * 0x1000)], // Echo RAM
        0xFE00...0xFE9F => self.gbc.bus.ppu.read_oam_cpu(address),
        0xFEA0...0xFEFF => 0, // Unusable
        0xFF00...0xFF7F => self.gbc.bus.io.read(address),
        0xFF80...0xFFFE => self.gbc.bus.HRAM[address - 0xFF80],
        0xFFFF => self.gbc.bus.IE,
    };
}
