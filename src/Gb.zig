const Gb = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Cpu = @import("Cpu.zig");
const Bus = @import("Bus.zig");

cpu: Cpu,
bus: Bus, // memory-mapped I/O
screen: [144 * 160]u8 = @splat(0), // 144x160 pixels

pub fn init(allocator: Allocator, rom: []const u8) !*Gb {
    // put GB instance on heap so self-references work
    const gb = try allocator.create(Gb);
    errdefer allocator.destroy(gb);

    // init modules
    gb.bus = Bus.init(gb);
    gb.cpu = Cpu.init(&gb.bus);

    // ---------------------- USED IN BLARGG TESTING ----------------------
    try gb.load_rom(allocator, rom);
    gb.cpu.regs.PC = 0x0100;
    gb.cpu.regs.setAF(0x01B0);
    gb.cpu.regs.setBC(0x0013);
    gb.cpu.regs.setDE(0x00D8);
    gb.cpu.regs.setHL(0x014D);
    gb.cpu.regs.SP = 0xFFFE;
    // --------------------------------------------------------------------

    return gb;
}

pub fn deinit(self: *Gb, allocator: Allocator) void {
    allocator.free(self.bus.ROM);
    allocator.destroy(self);
}

fn load_rom(self: *Gb, allocator: Allocator, rom_file: []const u8) !void {
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

pub fn run(self: *Gb) void {
    while (true) {
        self.step();
    }
}

pub fn step(self: *Gb) void {
    self.cpu.step() catch {
        const opcode = self.bus.read(self.cpu.regs.PC - 1);
        std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC - 1 });
        std.process.exit(1);
    };
}
