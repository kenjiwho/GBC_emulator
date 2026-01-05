const GB = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const CPU = @import("CPU.zig");
const Bus = @import("Bus.zig");
const Timer = @import("Timer.zig");

cpu: CPU,
timer: Timer,
bus: Bus, // memory-mapped I/O
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels

pub fn init(allocator: Allocator) !*GB {
    // put GB instance on heap so self-references work
    const gb = try allocator.create(GB);
    errdefer allocator.destroy(gb);

    // init modules
    gb.bus = Bus.init();
    gb.cpu = CPU.init(&gb.bus);
    gb.timer = Timer.init(&gb.bus);

    // connect modules to bus
    gb.bus.timer = &gb.timer;

    return gb;
}

pub fn deinit(self: *GB, allocator: Allocator) void {
    allocator.destroy(self);
}

pub fn load_rom(self: *GB, rom_file: []const u8) !void {
    const file = try std.fs.cwd().openFile(rom_file, .{ .mode = .read_only });
    defer file.close();
    var buffer: [0x4000]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;

    // ---------------------------- USED IN BLARGG TESTING ----------------------
    // check ROM size
    const rom_size = try file.getEndPos();
    if (rom_size > (self.bus.ROM_0.len + self.bus.ROM_S.len)) {
        std.debug.print("ROM size (${d} bytes) exceeds maximum supported size (${d} bytes)\n", .{ rom_size, self.bus.ROM_0.len });
        std.process.exit(1);
    }

    // read ROM into memory
    _ = try reader.readSliceShort(&self.bus.ROM_0);
    if (rom_size > self.bus.ROM_0.len) {
        _ = try reader.readSliceShort(&self.bus.ROM_S);
    }
    // -------------------------------------------------------------------------
}

pub fn run(self: *GB) void {
    // ----------------------- USED IN BLARGG TESTING -----------------------
    self.cpu.logState() catch {
        std.debug.print("CRASH: Failed to log CPU state at PC: ${X}\n", .{self.cpu.regs.PC});
        std.process.exit(1);
    };
    // ----------------------------------------------------------------------
    while (true) {
        self.step();
    }
}

pub fn step(self: *GB) void {
    self.cpu.step() catch {
        const opcode = self.bus.read(self.cpu.regs.PC - 1);
        std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC - 1 });
        std.process.exit(1);
    };
}
