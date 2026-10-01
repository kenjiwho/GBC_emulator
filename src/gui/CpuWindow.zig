//! cpu info window
const CpuInfo = @This();

const TextBox = @import("TextBox.zig");

text_box: TextBox,
text_buffer: [4096]u8 = undefined,

pub fn init() CpuInfo {
    return CpuInfo{
        .text_box = TextBox.init(10, 10, 620, 620),
    };
}

pub fn render(self: *CpuInfo) void {}
