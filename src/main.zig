const std = @import("std");
const Gbc = @import("Gbc.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    _ = args;

    // if (args.len != 2) {
    //     std.debug.print("Usage: {s} <path to rom>\n", .{args[0]});
    //     return;
    // }
    // const rom = args[1];

    // var gbc = try Gbc.init(allocator, rom);
    // var gbc = try Gbc.init(
    //     allocator,
    //     "./tests/mealybug/mealybug-tearoom-tests/m3_lcdc_bg_map_change.gb",
    //     "./tests/gbc_bios.bin",
    // );
    // var gbc = try Gbc.init(
    //     allocator,
    //     "./tests/mealybug/mealybug-tearoom-tests/m2_win_en_toggle.gb",
    //     "./tests/gbc_bios.bin",
    // );
    var gbc = try Gbc.init(
        io,
        gpa,
        "./tests/cgb-acid2.gbc",
        "./tests/gbc_bios.bin",
    );
    // var gbc = try Gbc.init(allocator, "./tests/blargg_test/halt_bug.gb");
    // var gbc = try Gbc.init(allocator, "./tests/mooneye/call_cc_timing.gb");
    // var gbc = try Gbc.init(allocator, "./.roms/Tetris.gb");
    defer gbc.deinit(gpa);

    try gbc.run();
}

test {
    _ = @import("tests/test_instrs.zig");
}
