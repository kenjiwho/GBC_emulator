const Gbc = @This();

const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});
const Allocator = std.mem.Allocator;
const Cpu = @import("Cpu.zig");
const Bus = @import("Bus.zig");
const Ppu = @import("Ppu.zig");

const DeviceMode = enum {
    DMG,
    CGB,
};

cpu: Cpu,
ppu: Ppu,
bus: Bus, // memory-mapped I/O
screen_texture: rl.Texture2D = undefined,
device_mode: DeviceMode = .DMG, // default to DMG mode

pub fn init(allocator: Allocator, rom: []const u8) !*Gbc {
    // put GB instance on heap so self-references work
    const gbc = try allocator.create(Gbc);
    errdefer allocator.destroy(gbc);

    // init modules
    gbc.bus = Bus.init(gbc);
    gbc.cpu = Cpu.init(&gbc.bus);
    gbc.ppu = Ppu.init(&gbc.bus);

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

pub fn run(self: *Gbc) void {
    rl.SetTargetFPS(144);
    rl.InitWindow(160 * 5, 144 * 5, "game window");
    defer rl.CloseWindow();

    // create an empty texture for the screen
    const image = rl.GenImageColor(Ppu.SCREEN_WIDTH, Ppu.SCREEN_HEIGHT, rl.BLACK);
    self.screen_texture = rl.LoadTextureFromImage(image);
    defer rl.UnloadTexture(self.screen_texture);
    rl.UnloadImage(image);

    // var accumulator: u32 = 0; // accumulator for frame timing

    while (!rl.WindowShouldClose()) {
        self.step_frame();
        self.draw();
    }
}

fn step_frame(self: *Gbc) void {
    self.cpu.step() catch {
        const opcode = self.bus.read(self.cpu.regs.PC - 1);
        std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC - 1 });
        std.process.exit(1);
    };

    const cycles = self.bus.timer.getLastCycles();

    self.ppu.step(cycles);
}

fn draw(self: *const Gbc) void {
    rl.BeginDrawing();
    defer rl.EndDrawing();

    rl.ClearBackground(rl.BLACK);
    rl.UpdateTexture(self.screen_texture, &self.ppu.screen);

    const source_rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = Ppu.SCREEN_WIDTH,
        .height = Ppu.SCREEN_HEIGHT,
    };
    const dest_rect = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = Ppu.SCREEN_WIDTH,
        .height = Ppu.SCREEN_HEIGHT,
    };
    const origin = rl.Vector2{ .x = 0, .y = 0 };

    rl.DrawTexturePro(self.screen_texture, source_rect, dest_rect, origin, 0, rl.WHITE);
}
