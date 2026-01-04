const GB = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const CPU = @import("CPU.zig");
const Bus = @import("Bus.zig");

cpu: CPU, // cpu
mmio: *Bus, // memory-mapped I/O
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels

pub fn init(allocator: Allocator) !GB {
    const bus = try allocator.create(Bus); // allocate memory for MMIO
    bus.* = Bus.init();
    const cpu = CPU.init(bus);

    const gb = GB{ .cpu = cpu, .mmio = bus };

    return gb;
}

pub fn deinit(self: *GB, allocator: Allocator) void {
    allocator.destroy(self.mmio);
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
    if (rom_size > (self.mmio.ROM_0.len + self.mmio.ROM_S.len)) {
        std.debug.print("ROM size (${d} bytes) exceeds maximum supported size (${d} bytes)\n", .{ rom_size, self.mmio.ROM_0.len });
        std.process.exit(1);
    }

    // read ROM into memory
    _ = try reader.readSliceShort(&self.mmio.ROM_0);
    if (rom_size > self.mmio.ROM_0.len) {
        _ = try reader.readSliceShort(&self.mmio.ROM_S);
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
        const opcode = self.mmio.read(self.cpu.regs.PC - 1);
        std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC - 1 });
        std.process.exit(1);
    };
}
