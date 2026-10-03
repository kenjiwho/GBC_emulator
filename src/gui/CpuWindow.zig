//! cpu info window
const CpuWindow = @This();

const std = @import("std");
const zsdl3 = @import("zsdl3");
const TextBox = @import("widgets/TextBox.zig");

window: *zsdl3.SDL_Window = undefined,
renderer: *zsdl3.SDL_Renderer = undefined,
text_box: TextBox,
text_buffer: [4096]u8 = undefined,
font: *zsdl3.ttf.TTF_Font,

pub fn init(font: *zsdl3.ttf.TTF_Font) CpuWindow {
    const window_height = 640;
    const window_width = 640;

    var cpu_window = CpuWindow{
        .text_box = TextBox.init(10, 10, window_width - 20, window_height - 20),
        .font = font,
    };

    cpu_window.window = zsdl3.createWindow(
        "Cpu window",
        window_width,
        window_height,
        zsdl3.SDL_WINDOW_RESIZABLE,
    ) orelse return error.SDLWindowFailed;

    cpu_window.renderer = zsdl3.createRenderer(cpu_window.window, null) orelse return error.SDLRendererFailed;

    return cpu_window;
}

pub fn deinit(self: *CpuWindow) void {
    zsdl3.destroyRenderer(self.renderer);
    zsdl3.destroyWindow(self.window);
}

pub fn render(self: *CpuWindow) void {
    _ = zsdl3.renderClear(self.renderer);

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
    self.text_box.render(self.renderer, self.font);

    _ = zsdl3.renderPresent(self.renderer);
}
