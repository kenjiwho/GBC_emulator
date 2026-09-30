const Gbc = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const zsdl3 = @import("zsdl3");
const Cpu = @import("cpu/Cpu.zig");
const Bus = @import("Bus.zig");
const Ppu = @import("ppu/Ppu.zig");
const Dma = @import("Dma.zig");
const Debugger = @import("Debugger.zig");
const helper = @import("helper.zig");

const DeviceMode = enum {
    DMG,
    CGB,
};

const CPU_CLOCK_HZ = 4_194_304;
const CYCLES_PER_FRAME = 70_224;
const NS_PER_FRAME: f64 = @as(f64, @floatFromInt(CYCLES_PER_FRAME)) * 1_000_000_000 / CPU_CLOCK_HZ;

cpu: Cpu,
ppu: Ppu,
bus: Bus,
dma: Dma,
window: *zsdl3.SDL_Window = undefined,
renderer: *zsdl3.SDL_Renderer = undefined,
screen_texture: *zsdl3.SDL_Texture = undefined,
device_mode: DeviceMode = undefined,

debugger: Debugger,

pub fn init(allocator: Allocator, rom: []const u8, boot_rom: []const u8) !*Gbc {
    // put GB instance on heap so self-references work
    const gbc = try allocator.create(Gbc);
    errdefer allocator.destroy(gbc);

    // init modules
    const bus = Bus.init(gbc);
    const cpu = Cpu.init(&gbc.bus);
    const ppu = Ppu.init(&gbc.bus);
    const dma = Dma.init(&gbc.bus, &gbc.ppu);
    const debugger = Debugger.init(gbc);

    gbc.* = Gbc{
        .cpu = cpu,
        .ppu = ppu,
        .bus = bus,
        .dma = dma,
        .debugger = debugger,
    };

    try gbc.load_rom(allocator, rom);
    try gbc.load_boot_rom(allocator, boot_rom);
    // set device mode based on ROM header
    gbc.device_mode = if (gbc.bus.ROM[0x143] == 0x80 or gbc.bus.ROM[0x143] == 0xC0) .CGB else .DMG;
    // gbc.setup_boot_state();

    return gbc;
}

pub fn deinit(self: *Gbc, allocator: Allocator) void {
    allocator.free(self.bus.ROM);
    allocator.free(self.bus.boot_ROM);
    allocator.destroy(self);
}

fn load_rom(self: *Gbc, allocator: Allocator, rom_file: []const u8) !void {
    const file = try std.fs.cwd().openFile(rom_file, .{ .mode = .read_only });
    defer file.close();
    var buffer: [0x4000]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;

    const rom_size = try file.getEndPos();
    const rom = try reader.readAlloc(allocator, rom_size);

    // read ROM into memory
    self.bus.insert_rom(rom);
}

fn load_boot_rom(self: *Gbc, allocator: Allocator, boot_rom_file: []const u8) !void {
    const file = try std.fs.cwd().openFile(boot_rom_file, .{ .mode = .read_only });
    defer file.close();
    var buffer: [0x1000]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;

    const boot_rom_size = try file.getEndPos();
    const boot_rom = try reader.readAlloc(allocator, boot_rom_size);

    // read boot ROM into memory
    self.bus.insert_boot_rom(boot_rom);
}

fn setup_boot_state(self: *Gbc) void {
    // set initial state of the CPU registers to what they should be
    // after the boot ROM has run
    if (self.device_mode == .CGB) {
        self.cpu.regs.setAF(0x1180);
        self.cpu.regs.setBC(0x0000);
        self.cpu.regs.setDE(0xFF56);
        self.cpu.regs.setHL(0x000D);
    } else {
        const old_license = self.bus.ROM[0x14B];
        const new_license = self.bus.ROM[0x144..0x146];
        var B: u8 = undefined;
        if (old_license == 0x01 or (old_license == 0x33 and new_license[0] == 0x30 and new_license[1] == 0x31)) {
            B = helper.sumArray(u8, self.bus.ROM[0x134..0x143]);
        } else {
            B = 0x00;
        }
        self.cpu.regs.setAF(0x1180);
        self.cpu.regs.setBC(@as(u16, B) << 8 | 0x00);
        self.cpu.regs.setDE(0x0008);
        if (B == 0x43 or B == 0x58) {
            self.cpu.regs.setHL(0x991A);
        } else {
            self.cpu.regs.setHL(0x007C);
        }
    }
    self.cpu.regs.PC = 0x0100;
    self.cpu.regs.SP = 0xFFFE;

    // set hardware registers to what they should be after the boot ROM has run
    self.bus.write(0xFF00, 0xC7); // P1
    self.bus.write(0xFF01, 0x00); // SB
    self.bus.write(0xFF02, 0x7F); // SC
    self.bus.write(0xFF04, 0xAB); // DIV
    self.bus.write(0xFF05, 0x00); // TIMA
    self.bus.write(0xFF06, 0x00); // TMA
    self.bus.write(0xFF07, 0xF8); // TAC
    self.bus.write(0xFF0F, 0xE1); // IF
    self.bus.write(0xFF10, 0x80); // NR10
    self.bus.write(0xFF11, 0xBF); // NR11
    self.bus.write(0xFF12, 0xF3); // NR12
    self.bus.write(0xFF13, 0xFF); // NR13
    self.bus.write(0xFF14, 0xBF); // NR14
    self.bus.write(0xFF16, 0x3F); // NR21
    self.bus.write(0xFF17, 0x00); // NR22
    self.bus.write(0xFF18, 0xFF); // NR23
    self.bus.write(0xFF19, 0xBF); // NR24
    self.bus.write(0xFF1A, 0x7F); // NR30
    self.bus.write(0xFF1B, 0xFF); // NR31
    self.bus.write(0xFF1C, 0x9F); // NR32
    self.bus.write(0xFF1D, 0xFF); // NR33
    self.bus.write(0xFF1E, 0xBF); // NR34
    self.bus.write(0xFF20, 0xFF); // NR41
    self.bus.write(0xFF21, 0x00); // NR42
    self.bus.write(0xFF22, 0x00); // NR43
    self.bus.write(0xFF23, 0xBF); // NR44
    self.bus.write(0xFF24, 0x77); // NR50
    self.bus.write(0xFF25, 0xF3); // NR51
    self.bus.write(0xFF26, 0xF1); // NR52
    self.bus.write(0xFF40, 0x91); // LCDC
    self.bus.write(0xFF41, 0x85); // STAT
    self.bus.write(0xFF42, 0x00); // SCY
    self.bus.write(0xFF43, 0x00); // SCX
    self.bus.write(0xFF44, 0x00); // LY
    self.bus.write(0xFF45, 0x00); // LYC
    self.bus.write(0xFF46, 0x00); // DMA
    self.bus.write(0xFF47, 0xFC); // BGP
    self.bus.write(0xFF48, 0x00); // OBP0
    self.bus.write(0xFF49, 0x00); // OBP1
    self.bus.write(0xFF4A, 0x00); // WY
    self.bus.write(0xFF4B, 0x00); // WX
    self.bus.write(0xFF4C, if (self.device_mode == .CGB) 0x04 else 0x00); // KEY1
    self.bus.write(0xFF4D, 0x7A); // KEY1
    self.bus.write(0xFF4F, 0xFE); // VBK
    self.bus.write(0xFF51, 0xFF); // HDMA1
    self.bus.write(0xFF52, 0xFF); // HDMA2
    self.bus.write(0xFF53, 0xFF); // HDMA3
    self.bus.write(0xFF54, 0xFF); // HDMA4
    self.bus.write(0xFF55, 0xFF); // HDMA5
    self.bus.write(0xFF56, 0x3E); // RP
    self.bus.write(0xFF68, 0x00); // BGPI
    self.bus.write(0xFF69, 0x00); // BGPD
    self.bus.write(0xFF6A, 0x00); // OBPI
    self.bus.write(0xFF6B, 0x00); // OBPD
    self.bus.write(0xFF70, 0xF8); // SVBK
    self.bus.write(0xFFFF, 0x00); // IE

    self.bus.boot_rom_enabled = false; // disable boot ROM after setup
}

pub fn run(self: *Gbc) !void {
    if (!zsdl3.init(zsdl3.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }
    defer zsdl3.quit();

    // Main game window
    self.window = zsdl3.createWindow(
        "Game Boy Color Emulator",
        Ppu.SCREEN_WIDTH * 5,
        Ppu.SCREEN_HEIGHT * 5,
        zsdl3.SDL_WINDOW_RESIZABLE,
    ) orelse return;
    defer zsdl3.destroyWindow(self.window);

    // renderer for the game window
    self.renderer = zsdl3.createRenderer(self.window, null) orelse return error.SDLRendererFailed;
    defer zsdl3.destroyRenderer(self.renderer);

    self.screen_texture = zsdl3.createTexture(
        self.renderer,
        zsdl3.SDL_PIXELFORMAT_ARGB8888,
        zsdl3.SDL_TEXTUREACCESS_STREAMING,
        Ppu.SCREEN_WIDTH,
        Ppu.SCREEN_HEIGHT,
    ) orelse return error.SDLTextureFailed;
    defer zsdl3.destroyTexture(self.screen_texture);

    var event: zsdl3.SDL_Event = undefined;
    var quit: bool = false;
    var last_time = zsdl3.getTicksNS();
    var accumulator: f64 = 0; // accumulator for frame timing
    while (!quit) {
        while (zsdl3.pollEvent(&event)) {
            if (event.type == zsdl3.SDL_EVENT_QUIT) {
                quit = true;
            }
        }

        const current_time = zsdl3.getTicksNS();
        const delta = current_time - last_time;
        accumulator += @floatFromInt(delta);
        last_time = current_time;

        while (accumulator >= NS_PER_FRAME) : (accumulator -= NS_PER_FRAME) {
            self.step_frame();
        }
        self.render();
    }
}

/// Execute CPU and PPU steps for one frame
fn step_frame(self: *Gbc) void {
    var frame_cycles: usize = 0;

    while (!self.ppu.frame_complete) {
        if (self.dma.counter > 0) {
            self.dma.step();
            std.debug.print("DMA TRANSFER HAPPENING\n", .{});
        } else {
            self.cpu.step() catch {
                const opcode = self.bus.read(self.cpu.regs.PC - 1);
                std.debug.print(
                    "CRASH opcode=${X} PC=${X} SP=${X} AF=${X} BC=${X} DE=${X} HL=${X}\n",
                    .{
                        opcode,
                        self.cpu.regs.PC - 1,
                        self.cpu.regs.SP,
                        self.cpu.regs.getAF(),
                        self.cpu.regs.getBC(),
                        self.cpu.regs.getDE(),
                        self.cpu.regs.getHL(),
                    },
                );
                std.debug.print(
                    "stack: [{X:0>4}]={X} [{X:0>4}]={X}\n",
                    .{
                        self.cpu.regs.SP,
                        self.bus.read(self.cpu.regs.SP),
                        self.cpu.regs.SP + 1,
                        self.bus.read(self.cpu.regs.SP + 1),
                    },
                );
                std.process.exit(1);
            };
        }

        const cycles = self.bus.timer.get_last_cycles();

        // if double speed mode is enabled, each CPU cycle takes 2 system cycles
        const is_double_speed = self.bus.io.getKey1().current_speed;
        const system_cycles = if (is_double_speed) cycles / 2 else cycles;

        self.ppu.step(system_cycles);
        frame_cycles += system_cycles;

        // if lcd is disabled, wait for 70224 cycles before breaking
        if (!self.ppu.lcdc.lcd_ppu_enable and frame_cycles >= CYCLES_PER_FRAME) {
            break;
        }
    }
    self.ppu.frame_complete = false;
}

/// Render the current screen to the window
fn render(self: *const Gbc) void {
    _ = zsdl3.renderClear(self.renderer);

    _ = zsdl3.updateTexture(
        self.screen_texture,
        null, // null means whole texture
        &self.ppu.screen,
        Ppu.SCREEN_WIDTH * 4, // pitch (bytes per row) = width * 4 (bytes per pixel)
    );

    _ = zsdl3.renderTexture(
        self.renderer,
        self.screen_texture,
        null, // src rect (null means whole texture)
        null, // dest rect (null means whole window)
    );

    _ = zsdl3.renderPresent(self.renderer);

    // rl.drawFPS(10, 10);
}
