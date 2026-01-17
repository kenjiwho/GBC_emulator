const Gbc = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("raylib");
const Cpu = @import("cpu/Cpu.zig");
const Bus = @import("Bus.zig");
const Ppu = @import("ppu/Ppu.zig");

const DeviceMode = enum {
    DMG,
    CGB,
};

const CPU_CLOCK_HZ = 4_194_304;
const CYCLES_PER_FRAME = 70_224;
const SECONDS_PER_FRAME: f64 = @as(f64, @floatFromInt(CYCLES_PER_FRAME)) / CPU_CLOCK_HZ;

cpu: Cpu,
ppu: Ppu,
bus: Bus, // memory-mapped I/O
screen_texture: rl.Texture2D = undefined,
debug_texture: rl.Texture2D = undefined,
device_mode: DeviceMode = .DMG, // default to DMG mode
cycles_executed: usize = 0, // cycles executed in current frame

pub fn init(allocator: Allocator, rom: []const u8) !*Gbc {
    // put GB instance on heap so self-references work
    const gbc = try allocator.create(Gbc);
    errdefer allocator.destroy(gbc);

    // init modules
    const bus = Bus.init(gbc);
    const cpu = Cpu.init(&gbc.bus);
    const ppu = Ppu.init(&gbc.bus);

    gbc.* = Gbc{
        .cpu = cpu,
        .ppu = ppu,
        .bus = bus,
    };

    // ---------------------- USED IN BLARGG TESTING ----------------------
    try gbc.load_rom(allocator, rom);
    gbc.cpu.regs.PC = 0x0100;
    gbc.cpu.regs.setAF(0x01B0);
    gbc.cpu.regs.setBC(0x0013);
    gbc.cpu.regs.setDE(0x00D8);
    gbc.cpu.regs.setHL(0x014D);
    gbc.cpu.regs.SP = 0xFFFE;
    // --------------------------------------------------------------------

    return gbc;
}

pub fn deinit(self: *Gbc, allocator: Allocator) void {
    allocator.free(self.bus.ROM);
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
    self.bus.insertROM(rom);
}

pub fn run(self: *Gbc) !void {
    rl.setTargetFPS(120);
    rl.initWindow(160 * 5, 144 * 5, "game window");
    defer rl.closeWindow();

    // create an empty texture for the screen
    const image = rl.genImageColor(Ppu.SCREEN_WIDTH, Ppu.SCREEN_HEIGHT, rl.Color.black);
    self.screen_texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(self.screen_texture);
    rl.unloadImage(image);

    // create an empty texture for the screen
    const debug_image = rl.genImageColor(Ppu.SCREEN_WIDTH, Ppu.SCREEN_HEIGHT, rl.Color.black);
    self.debug_texture = try rl.loadTextureFromImage(debug_image);
    defer rl.unloadTexture(self.debug_texture);
    rl.unloadImage(debug_image);

    var accumulator: f64 = 0; // accumulator for frame timing

    while (!rl.windowShouldClose()) {
        accumulator += rl.getFrameTime();
        while (accumulator >= SECONDS_PER_FRAME) : (accumulator -= SECONDS_PER_FRAME) {
            self.step_frame();
            self.cycles_executed -= CYCLES_PER_FRAME;
        }
        self.render();
    }
}

/// Execute CPU and PPU steps for one frame
fn step_frame(self: *Gbc) void {
    self.ppu.debug_screen = @splat(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    while (self.cycles_executed < CYCLES_PER_FRAME) {
        self.cpu.step() catch {
            const opcode = self.bus.read(self.cpu.regs.PC - 1);
            std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC - 1 });
            std.process.exit(1);
        };

        const cycles = self.bus.timer.getLastCycles();

        self.ppu.step(cycles);

        self.cycles_executed += cycles;
    }
}

/// Render the current screen to the window
fn render(self: *const Gbc) void {
    const window_width: f32 = @floatFromInt(rl.getScreenWidth());
    const window_height: f32 = @floatFromInt(rl.getScreenHeight());

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.black);
    rl.updateTexture(self.screen_texture, &self.ppu.screen);
    rl.updateTexture(self.debug_texture, &self.ppu.debug_screen);

    const source_rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = Ppu.SCREEN_WIDTH,
        .height = Ppu.SCREEN_HEIGHT,
    };
    const dest_rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = window_width,
        .height = window_height,
    };
    const origin = rl.Vector2{ .x = 0, .y = 0 };

    rl.drawTexturePro(self.screen_texture, source_rect, dest_rect, origin, 0, rl.Color.white);
    rl.drawTexturePro(self.debug_texture, source_rect, dest_rect, origin, 0, rl.Color.white);

    rl.drawFPS(10, 10);
}
