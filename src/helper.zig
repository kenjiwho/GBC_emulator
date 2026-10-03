//! general helper functions
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn sumArray(comptime T: type, arr: []const T) T {
    var sum: T = 0;
    for (arr) |value| {
        sum += value;
    }
    return sum;
}

pub fn readFile(io: Io, gpa: Allocator, file_path: []const u8) ![]u8 {
    const cwd = Io.Dir.cwd();
    const file = try cwd.openFile(io, file_path, .{ .mode = .read_only });
    defer file.close(io);

    const file_size = try file.length(io);
    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buffer);

    const data = try gpa.alloc(u8, file_size);

    file_reader.interface.readSliceAll(data) catch |err| {
        std.log.err("read failed: {}\n", .{err});
        return err;
    };

    return data;
}
