//! general helper functions
const std = @import("std");

pub fn sumArray(comptime T: type, arr: []const T) T {
    var sum: T = 0;
    for (arr) |value| {
        sum += value;
    }
    return sum;
}
