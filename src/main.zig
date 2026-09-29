const std = @import("std");
const Gbc = @import("Gbc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    // if (args.len != 2) {
    //     std.debug.print("Usage: {s} <path to rom>\n", .{args[0]});
    //     return;
    // }
    // const rom = args[1];

    // // var gbc = try Gbc.init(allocator, rom);
    var gbc = try Gbc.init(
        allocator,
        "./tests/mealybug/mealybug-tearoom-tests/m3_lcdc_bg_map_change.gb",
        "./tests/gbc_bios.bin",
    );
    // var gbc = try Gbc.init(
    //     allocator,
    //     "./tests/mealybug/mealybug-tearoom-tests/m2_win_en_toggle.gb",
    //     "./tests/gbc_bios.bin",
    // );
    // var gbc = try Gbc.init(allocator, "./tests/blargg_test/halt_bug.gb");
    // var gbc = try Gbc.init(allocator, "./tests/mooneye/call_cc_timing.gb");
    // var gbc = try Gbc.init(allocator, "./.roms/Tetris.gb");
    defer gbc.deinit(allocator);

    try gbc.run();
}

test {
    _ = @import("tests/test_instrs.zig");
}
