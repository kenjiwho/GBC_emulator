//! FIFO for background/window and object pixel data
const Fifo = @This();

const Error = error{ Overflow, Underflow };

const Pixel = struct {
    color_index: u2,
    palette: u3,
    sprite_priority: ?bool,
    background_priority: bool,
};

head: usize = 0, // index of first pixel in FIFO
tail: usize = 0, // where the next pixel will be added
count: usize = 0, // number of pixels currently in the FIFO
buffer: [16]Pixel = undefined, // pixel color indices

pub fn init() Fifo {
    return Fifo{};
}

/// Pushes row of 8 pixels into the FIFO from the provided tile data bytes
pub fn push(self: *Fifo, tile_data_low: u8, tile_data_high: u8) error{Overflow}!void {
    if (self.count + 8 > 16) {
        return Error.Overflow;
    }

    for (0..8) |i| {
        const color_index: u2 = @intCast((tile_data_high >> @intCast(7 - i) & 0x1) << 1 | (tile_data_low >> @intCast(7 - i) & 0x1));
        const pixel = Pixel{
            .color_index = color_index,
            .palette = 0,
            .sprite_priority = null,
            .background_priority = false,
        };
        self.buffer[self.tail] = pixel;
        self.tail = (self.tail + 1) % 16;
        self.count += 1;
    }
}

/// Pops a pixel from the front of the FIFO
pub fn pop(self: *Fifo) error{Underflow}!Pixel {
    if (self.count == 0) {
        return Error.Underflow;
    }
    const pixel = self.buffer[self.head];
    self.head = (self.head + 1) % 16;
    self.count -= 1;
    return pixel;
}
