const std = @import("std");
const Gbc = @import("Gbc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // try gb.load_rom("./tests/blargg_test/cpu_instrs/cpu_instrs.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/01-special.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/02-interrupts.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/03-op sp,hl.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/04-op r,imm.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/05-op rp.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/06-ld r,r.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/08-misc instrs.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/09-op r,r.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/10-bit ops.gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/11-op a,(hl).gb");
    // try gb.load_rom("./tests/blargg_test/cpu_instrs/individual/11-op a,(hl).gb");
    // try gb.load_rom("./tests/blargg_test/halt_bug.gb");
    var gbc = try Gbc.init(allocator, "./tests/blargg_test/cpu_instrs/cpu_instrs.gb");
    defer gbc.deinit(allocator);

    gbc.run();
}

test {
    _ = @import("tests/test_instrs.zig");
}
