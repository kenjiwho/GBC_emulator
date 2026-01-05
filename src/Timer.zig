const Timer = @This();

const Bus = @import("Bus.zig");

counter: u16 = 0,
TIMA: u8 = 0,
TMA: u8 = 0, // controls TIMA reset value
TAC: u8 = 0b0000, // controls TIMA speed
reload_delay: u3 = 0, // delay counter for TIMA reload
bus: *Bus = undefined, // reference to the bus for interrupt requests

pub fn init(bus: *Bus) Timer {
    return Timer{ .bus = bus };
}

// tick the timer by 4 T_cycles
pub fn tick(self: *Timer) void {
    const TIMA_enabled = (self.TAC & 0b100) != 0;
    // the bit that determines when to increment TIMA
    const TIMA_bit = switch (self.TAC & 0b11) {
        0b00 => 9,
        0b01 => 3,
        0b10 => 5,
        0b11 => 7,
        else => unreachable,
    };

    var prev_signal = (self.counter >> TIMA_bit) & 0b1;
    // increment the counter 4 times (once per T_cycle)
    for (0..4) |_| {
        // handle TIMA reload delay
        if (self.reload_delay > 0) {
            self.reload_delay -= 1;
            if (self.reload_delay == 0) {
                self.TIMA = self.TMA;
                self.bus.requestInterrupt(.Timer);
            }
        }

        self.counter +%= 1;

        // check for TIMA increment
        if (TIMA_enabled) {
            const curr_signal = (self.counter >> TIMA_bit) & 0b1;
            if (prev_signal == 1 and curr_signal == 0) {
                self.TIMA +%= 1;
                if (self.TIMA == 0) {
                    // TIMA has overflowed
                    self.reload_delay = 4; // reset TIMA after 4 T_cycles
                }
            }
            prev_signal = curr_signal;
        }
    }
}

pub fn readDIV(self: *Timer) u8 {
    return self.counter >> 8;
}
