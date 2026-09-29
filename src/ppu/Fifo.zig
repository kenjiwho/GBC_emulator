//! FIFO for background/window and object pixel data
const Fifo = @This();

const Error = error{ Overflow, Underflow };
const Pixel = @import("ppu_structs.zig").Pixel;

head: usize = 0, // index of first pixel in FIFO
tail: usize = 0, // where the next pixel will be added
count: usize = 0, // number of pixels currently in the FIFO
buffer: [8]Pixel = undefined, // pixel color indices

pub fn init() Fifo {
    return Fifo{};
}

/// Pushes row of 8 pixels into the FIFO from the provided tile data bytes
pub fn push(self: *Fifo, tile_data_low: u8, tile_data_high: u8, x_flip: bool) error{Overflow}!void {
    if (self.count + 8 > self.buffer.len) {
        return Error.Overflow;
    }

    // push pixels in reverse order if x_flip is true
    var i: i8 = if (x_flip) 7 else 0;
    const adder: i8 = if (x_flip) -1 else 1;
    while (i < self.buffer.len) : (i += adder) {
        const pixel_low = (tile_data_low >> @intCast(7 - i)) & 0x1;
        const pixel_high = (tile_data_high >> @intCast(7 - i)) & 0x1;
        const color_index: u2 = @intCast((pixel_high) << 1 | pixel_low);
        const pixel = Pixel{
            .color_index = color_index,
            .palette = null,
            .background_priority = false,
        };
        self.buffer[self.tail] = pixel;
        self.tail = (self.tail + 1) % self.buffer.len;
        self.count += 1;
    }
}

// TODO: add pallette attribute
/// Mixes row of 8 pixels with existing pixels in FIFO
pub fn mix(self: *Fifo, tile_data_low: u8, tile_data_high: u8, x_flip: bool, priority: bool) void {
    for (0..8) |i| {
        const bit_idx: u3 = if (x_flip) @intCast(i) else @intCast(7 - i);

        const pixel_low = (tile_data_low >> bit_idx) & 1;
        const pixel_high = (tile_data_high >> bit_idx) & 1;
        const color_index: u2 = @intCast((pixel_high << 1) | pixel_low);

        const new_pixel = Pixel{
            .color_index = color_index,
            .palette = null,
            .background_priority = priority,
        };

        if (i < self.count) {
            // OVERLAP
            const buffer_idx = (self.head + i) % self.buffer.len;

            // replace if existing pixel is transparent
            if (self.buffer[buffer_idx].color_index == 0 and color_index != 0) {
                self.buffer[buffer_idx] = new_pixel;
            }
        } else {
            // APPEND
            self.buffer[self.tail] = new_pixel;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;
        }
    }
}

/// Pops a pixel from the front of the FIFO
pub fn pop(self: *Fifo) error{Underflow}!Pixel {
    if (self.count == 0) {
        return Error.Underflow;
    }
    const pixel = self.buffer[self.head];
    self.head = (self.head + 1) % self.buffer.len;
    self.count -= 1;
    return pixel;
}

/// Clears the FIFO
pub fn clear(self: *Fifo) void {
    self.head = 0;
    self.tail = 0;
    self.count = 0;
}
