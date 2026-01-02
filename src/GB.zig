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

pub fn step(self: *GB) void {
    self.cpu.step() catch {
        const opcode = self.mmio.read(self.cpu.regs.PC - 1);
        std.debug.print("CRASH: Attempted to execute invalid opcode: ${X} at PC: ${X}\n", .{ opcode, self.cpu.regs.PC - 1 });
        std.process.exit(1);
    };
}
