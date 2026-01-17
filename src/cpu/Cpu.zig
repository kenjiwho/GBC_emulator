//! CPU module: implements the main CPU functionality
const Cpu = @This();

const Registers = @import("Registers.zig");
const Bus = @import("../Bus.zig");
const instrs = @import("instrs.zig");

opcode: u8 = 0, // current opcode
regs: Registers = Registers.init(), // 8x8-bit registers or 4x16-bit registers (AF, BC, DE, HL) + stack pointer + program counter
IME: bool = false,
IME_scheduled: bool = false, // whether to enable IME after next instruction
halted: bool = false,
halted_timer: i19 = -1,
stopped: bool = false,
HALT_bug: bool = false, // whether the HALT bug should be simulated
bus: *Bus, // reference to the bus struct so instructions can interact with memory

pub const Error = error{
    InvalidOpcode,
};

pub fn init(bus: *Bus) Cpu {
    return Cpu{ .bus = bus };
}

/// perform a single CPU step with IME, HALT, and interrupt handling
pub fn step(self: *Cpu) Error!void {
    const IE = self.bus.IE;
    const IF = self.bus.io.getIF();
    const pending_interrupts = IE & IF;

    // handle STOP state
    if (self.stopped) {
        return;
    }

    // handle HALT state
    if (self.halted) {
        if (pending_interrupts != 0) {
            self.halted = false;
        } else if (self.halted_timer == 0) {
            self.halted = false;
            self.halted_timer = -1;
        } else {
            self.internalCycle(); // advance timer while halted
            if (self.halted_timer > 0) {
                self.halted_timer -= 4;
            }
            return;
        }
    }

    if (self.IME and pending_interrupts != 0) {
        return self.serviceInterrupt(pending_interrupts);
    }

    // handle IME scheduling
    const next_IME = self.IME_scheduled;

    self.opcode = self.fetch();
    try instrs.execute(self);

    if (next_IME) {
        self.IME = true;
        self.IME_scheduled = false;
    }
}

// --------------------------------- helper functions ----------------------
/// Fetches the opcode at the current PC and increments PC
/// If the HALT bug is active, the PC is not incremented for this fetch
/// Cycles: 1
pub fn fetch(self: *Cpu) u8 {
    const opcode = self.bus.read(self.regs.PC);

    self.regs.PC +%= 1;

    // handle HALT bug
    if (self.HALT_bug) {
        self.regs.PC -%= 1;
        self.HALT_bug = false;
    }

    return opcode;
}

/// Gets flag from flags register
pub fn getFlag(self: *const Cpu, flag: Registers.Flag) bool {
    const bit: u3 = @intFromEnum(flag);

    return ((self.regs.F >> bit) & 0b1) == 1;
}

/// Sets the flags register
pub fn setFlag(self: *Cpu, flag: Registers.Flag, value: bool) void {
    const bit: u3 = @intFromEnum(flag);

    if (value) {
        self.regs.F |= @as(u8, 1) << bit;
    } else {
        self.regs.F &= ~(@as(u8, 1) << bit);
    }
}

/// Check a condition code
pub fn checkCondition(self: *const Cpu, condition: u2) bool {
    return switch (condition) {
        0 => !self.getFlag(.Z), // NZ
        1 => self.getFlag(.Z), // Z
        2 => !self.getFlag(.C), // NC
        3 => self.getFlag(.C), // C
    };
}

/// Gets the value of an 8-bit register using an index
/// Cycles: 1 if register is (HL), 0 otherwise
pub fn getR8(self: *const Cpu, register: u3) u8 {
    return switch (register) {
        0 => self.regs.B,
        1 => self.regs.C,
        2 => self.regs.D,
        3 => self.regs.E,
        4 => self.regs.H,
        5 => self.regs.L,
        6 => { // read from memory pointed to by HL
            const addr = self.regs.getHL();
            return self.bus.read(addr);
        },
        7 => self.regs.A,
    };
}

/// Sets the value of an 8-bit register using an index
/// Cycles: 1 if register is (HL), 0 otherwise
pub fn setR8(self: *Cpu, register: u3, value: u8) void {
    switch (register) {
        0 => self.regs.B = value,
        1 => self.regs.C = value,
        2 => self.regs.D = value,
        3 => self.regs.E = value,
        4 => self.regs.H = value,
        5 => self.regs.L = value,
        6 => { // write to memory pointed to by HL
            const addr = self.regs.getHL();
            self.bus.write(addr, value);
        },
        7 => self.regs.A = value,
    }
}

/// Gets the value of a 16-bit register pair using an index
pub fn getR16(self: *const Cpu, register: u2) u16 {
    return switch (register) {
        0 => self.regs.getBC(),
        1 => self.regs.getDE(),
        2 => self.regs.getHL(),
        3 => self.regs.SP,
    };
}

/// Sets the value of a 16-bit register pair using an index
pub fn setR16(self: *Cpu, register: u2, value: u16) void {
    switch (register) {
        0 => self.regs.setBC(value),
        1 => self.regs.setDE(value),
        2 => self.regs.setHL(value),
        3 => self.regs.SP = value,
    }
}

/// Gets the address pointed to by a 16-bit register pair using an index, with
/// optional increment/decrement for HL.
pub fn getR16mem(self: *Cpu, register: u2) u16 {
    return switch (register) {
        0, 1 => self.getR16(register), // BC or DE
        2 => { // HLI
            const addr = self.regs.getHL();
            self.regs.setHL(addr +% 1);
            return addr;
        },
        3 => { // HLD
            const addr = self.regs.getHL();
            self.regs.setHL(addr -% 1);
            return addr;
        },
    };
}

// Gets the value of a r16stk register index
pub fn getR16stk(self: *const Cpu, register: u2) u16 {
    return switch (register) {
        0, 1, 2 => self.getR16(register), // BC, DE, HL
        3 => self.regs.getAF(),
    };
}

// Sets the value of a r16stk register index
pub fn setR16stk(self: *Cpu, register: u2, value: u16) void {
    switch (register) {
        0, 1, 2 => self.setR16(register, value),
        3 => self.regs.setAF(value),
    }
}

/// Fetches a 8-bit immediate value from the instruction stream
/// Cycles: 1
pub fn getImm8(self: *Cpu, T: type) T {
    return @bitCast(self.fetch());
}

/// Fetches a 16-bit immediate value from the instruction stream
/// Cycles: 2
pub fn getImm16(self: *Cpu) u16 {
    const low = self.fetch();
    const high = self.fetch();
    return (@as(u16, high) << 8) | low;
}

/// pop a 16-bit value from the stack
/// Cycles: 2
pub fn pop(self: *Cpu) u16 {
    const low = self.bus.read(self.regs.SP);
    const high = self.bus.read(self.regs.SP +% 1);
    self.regs.SP +%= 2;

    return (@as(u16, high) << 8) | low;
}

/// push a 16-bit value onto the stack
/// Cycles: 3
pub fn push(self: *Cpu, value: u16) void {
    self.internalCycle();
    self.regs.SP -%= 2;
    self.bus.write(self.regs.SP +% 1, @intCast(value >> 8));
    self.bus.write(self.regs.SP, @intCast(value & 0xFF));
}

/// calls timer.tick() to advance the timer by 4 T_cycles
/// Some operations cost cycles without memory access
pub fn internalCycle(self: *Cpu) void {
    self.bus.timer.tick();
}

/// service an interrupt
/// Cycles: 5
fn serviceInterrupt(self: *Cpu, pending_interrupts: u8) void {
    self.IME = false;

    // find highest priority interrupt
    // @ctz counts trailing zeros, so we can use it to find the index of the
    // lowest set bit which is the highest priority interrupt
    const interrupt_num: u3 = @intCast(@ctz(pending_interrupts));
    const interrupt_vector = 0x40 + @as(u8, interrupt_num) * 0x08;

    // clear current handled interrupt flag
    const IF = self.bus.io.getIF();
    const bit_mask = @as(u8, 1) << interrupt_num;
    self.bus.io.setIF(IF & ~bit_mask);

    // jump to interrupt handler
    self.internalCycle();
    self.push(self.regs.PC);
    self.internalCycle();
    self.regs.PC = interrupt_vector;
}

// --------------------------------- end helper functions ------------------
