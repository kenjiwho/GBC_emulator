const Timer = @This();

const Bus = @import("Bus.zig");

// registers
counter: u16 = 0, // internal counter/DIV
TIMA: u8 = 0,
TMA: u8 = 0, // controls TIMA reset value
TAC: u8 = 0b0000, // controls TIMA speed

prev_signal: bool = false, // previous state of the selected TIMA bit
reload_delay: u3 = 0, // delay counter for TIMA reload
bus: *Bus, // reference to the bus for interrupt requests
last_cycles_taken: usize = 0, // number of T_cycles taken for last cpu step

pub fn init(bus: *Bus) Timer {
    return Timer{ .bus = bus };
}

// tick the timer by 4 T_cycles
pub fn tick(self: *Timer) void {
    // increment the counter 4 times (once per T_cycle)
    for (0..4) |_| {
        // handle TIMA reload delay
        if (self.reload_delay > 0) {
            self.reload_delay -= 1;
            if (self.reload_delay == 0) {
                self.TIMA = self.TMA;
                self.bus.io.requestInterrupt(.timer);
            }
        }

        self.counter +%= 1;
        self.last_cycles_taken += 1;

        self.timaIncrementCheck();
    }
}

fn timaIncrementCheck(self: *Timer) void {
    const TIMA_enabled = (self.TAC & 0b100) != 0;
    // the bit that determines when to increment TIMA
    const TIMA_bit: u4 = switch (self.TAC & 0b11) {
        0b00 => 9,
        0b01 => 3,
        0b10 => 5,
        0b11 => 7,
        else => unreachable,
    };

    const curr_signal = ((self.counter >> TIMA_bit) & 0b1) == 1;

    // check for TIMA increment
    // TAC bit 2 should be set,
    // no reload should be pending,
    // and there should be a falling edge on the selected bit
    if (TIMA_enabled and
        self.reload_delay == 0 and
        (self.prev_signal and !curr_signal))
    {
        self.TIMA +%= 1;
        if (self.TIMA == 0) {
            // TIMA has overflowed
            self.reload_delay = 4; // reset TIMA after 4 T_cycles
        }
    }

    self.prev_signal = curr_signal;
}

pub fn getLastCycles(self: *Timer) usize {
    const cycles = self.last_cycles_taken;
    self.last_cycles_taken = 0;
    return cycles;
}

pub fn read(self: *Timer, address: u16) u8 {
    return switch (address) {
        0xFF04 => @intCast(self.counter >> 8), // DIV
        0xFF05 => self.TIMA,
        0xFF06 => self.TMA,
        0xFF07 => self.TAC | 0b11111000, // unused bits read as 1
        else => unreachable,
    };
}

pub fn write(self: *Timer, address: u16, value: u8) void {
    switch (address) {
        0xFF04 => { // writing to DIV resets it
            self.counter = 0;
            // resetting DIV can cause TIMA to increment
            self.timaIncrementCheck();
        },
        0xFF05 => {
            self.TIMA = value;
            // cancel any pending reload
            self.reload_delay = 0;
        },
        0xFF06 => {
            self.TMA = value;
        },
        0xFF07 => {
            self.TAC = value & 0b00000111; // unused bits always 0
            // updating TAC can cause TIMA to increment
            self.timaIncrementCheck();
        },
        else => unreachable,
    }
}
