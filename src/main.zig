const std = @import("std");
const Gbc = @import("Gbc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        std.debug.print("Usage: {s} <path to rom>\n", .{args[0]});
        return;
    }
    const rom = args[1];

    var gbc = try Gbc.init(allocator, rom);
    // var gbc = try Gbc.init(allocator, "./tests/blargg_test/cpu_instrs/cpu_instrs.gb");
    // var gbc = try Gbc.init(allocator, "./.roms/mealybug/m2_win_en_toggle.gb");
    // var gbc = try Gbc.init(allocator, "./.roms/Tetris.gb");
    defer gbc.deinit(allocator);

    try gbc.run();
}

test {
    _ = @import("tests/test_instrs.zig");
}
