const std = @import("std");
const GB = @import("GB.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gb = try GB.init(allocator);
    defer gb.deinit(allocator);

    // ---------------------- USED IN BLARGG TESTING ----------------------
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/01-special.gb");
    try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/02-interrupts.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/03-op sp,hl.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/04-op r,imm.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/05-op rp.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/06-ld r,r.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/08-misc instrs.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/09-op r,r.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/10-bit ops.gb");
    // try gb.load_rom("./.roms/blargg_test/cpu_instrs/individual/11-op a,(hl).gb");
    gb.cpu.regs.PC = 0x0100;
    gb.cpu.regs.setAF(0x01B0);
    gb.cpu.regs.setBC(0x0013);
    gb.cpu.regs.setDE(0x00D8);
    gb.cpu.regs.setHL(0x014D);
    gb.cpu.regs.SP = 0xFFFE;
    // --------------------------------------------------------------------
    gb.run();
}

test {
    _ = @import("CPU.zig");
}
