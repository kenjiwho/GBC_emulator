//! Window manager for the emulator
const WindowManager = @This();

const std = @import("std");

const zsdl3 = @import("zsdl3");

pub fn init() WindowManager {
    return WindowManager{};
}
