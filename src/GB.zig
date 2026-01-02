const GB = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const CPU = @import("CPU.zig");
const MMIO = @import("MMIO.zig");

cpu: CPU, // cpu
mmio: *MMIO, // memory-mapped I/O
screen: [160 * 144]u8 = @splat(0), // 160x144 pixels

pub fn init(allocator: Allocator) !GB {
    const mmio = try allocator.create(MMIO);
    const cpu = CPU.init(mmio);

    const gb = GB{ .cpu = cpu, .mmio = mmio };

    return gb;
}

pub fn deinit(self: *GB, allocator: Allocator) void {
    allocator.destroy(self.mmio);
}

pub fn step(self: *GB) void {
    self.cpu.execute() catch {
        const opcode = self.mmio.read(self.cpu.regs.PC);
        std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC });
        std.process.exit(1);
    };
    self.cpu.regs.PC +%= 1;
}
