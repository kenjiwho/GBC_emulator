//! CPU module: implements the main CPU functionality
const CPU = @This();

const std = @import("std");
const Registers = @import("Registers.zig");
const Bus = @import("Bus.zig");

// opcode function type
const DispatchFn = *const fn (self: *CPU) CpuError!void;

opcode: u8 = 0, // current opcode
regs: Registers = Registers.init(), // 8x8-bit registers or 4x16-bit registers (AF, BC, DE, HL) + stack pointer + program counter
IME: bool = false,
IME_scheduled: bool = false, // whether to enable IME after next instruction
halted: bool = false,
HALT_bug: bool = false, // whether the HALT bug should be simulated
bus: *Bus, // reference to the bus struct so instructions can interact with memory
comptime dispatch_ptr_tbl: [4]DispatchFn = .{
    dispatch0,
    dispatch1,
    dispatch2,
    dispatch3,
},

pub const CpuError = error{
    InvalidOpcode,
};

pub fn init(bus: *Bus) CPU {
    return CPU{ .bus = bus };
}

/// perform a single CPU step with IME, HALT, and interrupt handling
pub fn step(self: *CPU) !void {
    const IE = self.bus.getIE();
    const IF = self.bus.getIF();
    const pending_interrupts = IE & IF;

    // handle HALT state
    if (self.halted) {
        if (pending_interrupts != 0) {
            self.halted = false;
        } else {
            self.internalCycle(); // advance timer while halted
            return;
        }
    }

    if (self.IME and pending_interrupts != 0) {
        return self.serviceInterrupt(pending_interrupts);
    }

    // handle IME scheduling
    const next_IME = self.IME_scheduled;

    try self.execute();
    // ----------------------- USED IN BLARGG TESTING -----------------------
    try self.logState();
    // ----------------------------------------------------------------------

    if (next_IME) {
        self.IME = true;
        self.IME_scheduled = false;
    }
}

// ----------------------- USED IN BLARGG TESTING -----------------------
pub fn logState(self: *const CPU) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.createFile("./blargg.log", .{ .truncate = false });
    defer file.close();
    var buffer: [256]u8 = undefined;
    try file.seekFromEnd(0);

    const state = try std.fmt.bufPrint(&buffer, "A:{X:02} F:{X:02} B:{X:02} C:{X:02} D:{X:02} E:{X:02} H:{X:02} L:{X:02} SP:{X:04} PC:{X:04} PCMEM:{X:02},{X:02},{X:02},{X:02}\n", .{
        self.regs.A,
        self.regs.F,
        self.regs.B,
        self.regs.C,
        self.regs.D,
        self.regs.E,
        self.regs.H,
        self.regs.L,
        self.regs.SP,
        self.regs.PC,
        self.bus.read_no_tick(self.regs.PC),
        self.bus.read_no_tick(self.regs.PC + 1),
        self.bus.read_no_tick(self.regs.PC + 2),
        self.bus.read_no_tick(self.regs.PC + 3),
    });

    _ = try file.write(state);
}
// ----------------------------------------------------------------------

fn serviceInterrupt(self: *CPU, pending_interrupts: u8) void {
    self.IME = false;

    // find highest priority interrupt
    // @ctz counts trailing zeros, so we can use it to find the index of the
    // lowest set bit which is the highest priority interrupt
    const interrupt_num: u3 = @intCast(@ctz(pending_interrupts));
    const interrupt_vector = 0x40 + @as(u8, interrupt_num) * 0x08;

    // jump to interrupt handler
    self.push(self.regs.PC);
    self.regs.PC = interrupt_vector;

    const IF = self.bus.read(0xFF0F);
    const bit_mask = @as(u8, 1) << interrupt_num;
    // clear current handled interrupt flag
    self.bus.write(0xFF0F, IF & ~bit_mask);
}

/// execute the next instruction (fetch-decode-execute)
fn execute(self: *CPU) !void {
    self.opcode = self.fetch();
    try self.dispatch_ptr_tbl[(self.opcode >> 6)](self);
}

// --------------------------------- opcode dispatchers --------------------
fn dispatch0(self: *CPU) CpuError!void {
    switch (self.opcode) { // full opcode
        0x00 => self.NOP(),
        0x08 => self.LD_imm16_SP(),
        0x18 => self.JR_imm8(),
        0x10 => self.STOP(),
        0x07 => self.RLCA(),
        0x0F => self.RRCA(),
        0x17 => self.RLA(),
        0x1F => self.RRA(),
        0x27 => self.DAA(),
        0x2F => self.CPL(),
        0x37 => self.SCF(),
        0x3F => self.CCF(),
        0x20, 0x28, 0x30, 0x38 => self.JR_cond_imm8(),
        else => {
            switch (self.opcode & 0xF) { // lower 4 bits
                0x1 => self.LD_r16_imm16(),
                0x2 => self.LD_r16mem_A(),
                0x3 => self.INC_r16(),
                0x4, 0xC => self.INC_r8(),
                0x5, 0xD => self.DEC_r8(),
                0x6, 0xE => self.LD_r8_imm8(),
                0x9 => self.ADD_HL_r16(),
                0xA => self.LD_A_r16mem(),
                0xB => self.DEC_r16(),
                else => unreachable,
            }
        },
    }
}
fn dispatch1(self: *CPU) CpuError!void {
    switch (self.opcode) { // full opcode
        0x76 => self.HALT(),
        else => self.LD_r8_r8(),
    }
}
fn dispatch2(self: *CPU) CpuError!void {
    switch (self.opcode >> 3) { // upper 5 bits
        0b10000 => self.ADD_A_r8(),
        0b10001 => self.ADC_A_r8(),
        0b10010 => self.SUB_A_r8(),
        0b10011 => self.SBC_A_r8(),
        0b10100 => self.AND_A_r8(),
        0b10101 => self.XOR_A_r8(),
        0b10110 => self.OR_A_r8(),
        0b10111 => self.CP_A_r8(),
        else => unreachable,
    }
}
fn dispatch3(self: *CPU) CpuError!void {
    switch (self.opcode) { // full opcode
        0xC6 => self.ADD_A_imm8(),
        0xCE => self.ADC_A_imm8(),
        0xD6 => self.SUB_A_imm8(),
        0xDE => self.SBC_A_imm8(),
        0xE6 => self.AND_A_imm8(),
        0xEE => self.XOR_A_imm8(),
        0xF6 => self.OR_A_imm8(),
        0xFE => self.CP_A_imm8(),
        0xC9 => self.RET(),
        0xD9 => self.RETI(),
        0xC3 => self.JP_imm16(),
        0xE9 => self.JP_HL(),
        0xCD => self.CALL_imm16(),
        0xCB => self.CB_prefix(),
        0xE2 => self.LDH_C_A(),
        0xE0 => self.LDH_imm8_A(),
        0xEA => self.LD_imm16_A(),
        0xF2 => self.LDH_A_C(),
        0xF0 => self.LDH_A_imm8(),
        0xFA => self.LD_A_imm16(),
        0xE8 => self.ADD_SP_imm8(),
        0xF8 => self.LD_HL_SPimm8(),
        0xF9 => self.LD_SP_HL(),
        0xF3 => self.DI(),
        0xFB => self.EI(),
        // invalid opcodes
        0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD => return CPU.CpuError.InvalidOpcode,
        else => {
            switch (self.opcode & 0b111) { // lower 3 bits
                0b000 => self.RET_cond(),
                0b001 => self.POP_r16stk(),
                0b010 => self.JP_cond_imm16(),
                0b100 => self.CALL_cond_imm16(),
                0b101 => self.PUSH_r16stk(),
                0b111 => self.RST_tgt3(),
                else => unreachable,
            }
        },
    }
}

// --------------------------------- helper functions ----------------------
/// Fetches the opcode at the current PC and increments PC
/// If the HALT bug is active, the PC is not incremented for this fetch
/// Cycles: 1
fn fetch(self: *CPU) u8 {
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
fn getFlag(self: *const CPU, flag: Registers.Flag) bool {
    const bit: u3 = @intFromEnum(flag);

    return ((self.regs.F >> bit) & 0b1) == 1;
}

/// Sets the flags register
fn setFlag(self: *CPU, flag: Registers.Flag, value: bool) void {
    const bit: u3 = @intFromEnum(flag);

    if (value) {
        self.regs.F |= @as(u8, 1) << bit;
    } else {
        self.regs.F &= ~(@as(u8, 1) << bit);
    }
}

/// Check a condition code
fn checkCondition(self: *const CPU, condition: u2) bool {
    return switch (condition) {
        0 => !self.getFlag(.Z), // NZ
        1 => self.getFlag(.Z), // Z
        2 => !self.getFlag(.C), // NC
        3 => self.getFlag(.C), // C
    };
}

/// Gets the value of an 8-bit register using an index
/// Cycles: 1 if register is (HL), 0 otherwise
fn getR8(self: *const CPU, register: u3) u8 {
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
fn setR8(self: *CPU, register: u3, value: u8) void {
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
fn getR16(self: *const CPU, register: u2) u16 {
    return switch (register) {
        0 => self.regs.getBC(),
        1 => self.regs.getDE(),
        2 => self.regs.getHL(),
        3 => self.regs.SP,
    };
}

/// Sets the value of a 16-bit register pair using an index
fn setR16(self: *CPU, register: u2, value: u16) void {
    switch (register) {
        0 => self.regs.setBC(value),
        1 => self.regs.setDE(value),
        2 => self.regs.setHL(value),
        3 => self.regs.SP = value,
    }
}

/// Gets the address pointed to by a 16-bit register pair using an index, with
/// optional increment/decrement for HL.
fn getR16mem(self: *CPU, register: u2) u16 {
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
fn getR16stk(self: *const CPU, register: u2) u16 {
    return switch (register) {
        0, 1, 2 => self.getR16(register), // BC, DE, HL
        3 => self.regs.getAF(),
    };
}

// Sets the value of a r16stk register index
fn setR16stk(self: *CPU, register: u2, value: u16) void {
    switch (register) {
        0, 1, 2 => self.setR16(register, value),
        3 => self.regs.setAF(value),
    }
}

/// Fetches a 8-bit immediate value from the instruction stream
/// Cycles: 1
fn getImm8(self: *CPU, T: type) T {
    return @bitCast(self.fetch());
}

/// Fetches a 16-bit immediate value from the instruction stream
/// Cycles: 2
fn getImm16(self: *CPU) u16 {
    const low = self.fetch();
    const high = self.fetch();
    return (@as(u16, high) << 8) | low;
}

/// pop a 16-bit value from the stack
/// Cycles: 2
fn pop(self: *CPU) u16 {
    const low = self.bus.read(self.regs.SP);
    const high = self.bus.read(self.regs.SP +% 1);
    self.regs.SP +%= 2;

    return (@as(u16, high) << 8) | low;
}

/// push a 16-bit value onto the stack
/// Cycles: 3
fn push(self: *CPU, value: u16) void {
    self.internalCycle();
    self.regs.SP -%= 2;
    self.bus.write(self.regs.SP +% 1, @intCast(value >> 8));
    self.bus.write(self.regs.SP, @intCast(value & 0xFF));
}

/// calls timer.tick() to advance the timer by 4 T_cycles
/// Some operations cost cycles without memory access
fn internalCycle(self: *CPU) void {
    self.bus.timer.tick();
}

// --------------------------------- end helper functions ------------------

// --------------------------------- CPU Instructions -------------------------
// --------------------------------- block 0 ----------------------------------
/// 00000000: NOP: No Operation
///
/// Cycles: 1
/// Bytes: 1
fn NOP(self: *const CPU) void {
    _ = self;
}

/// 00[r16]0001[imm16]: LD r16, imm16: Copy the value imm16 into register r16
///
/// Cycles: 3
/// Bytes: 3
fn LD_r16_imm16(self: *CPU) void {
    const r16: u2 = @intCast((self.opcode >> 4) & 0b11);
    const imm16 = self.getImm16();

    self.setR16(r16, imm16);
}

/// 00[r16mem]0010: LD [r16mem], A: Store value of register A into memory pointed to by r16mem
/// (if hli/hld, increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_r16mem_A(self: *CPU) void {
    const r16mem: u2 = @intCast((self.opcode >> 4) & 0b11);
    const addr = self.getR16mem(r16mem);

    self.bus.write(addr, self.regs.A);
}

/// 00[r16mem]1010: LD A, [r16mem]: Load value of memory pointed to by r16mem into register A
/// (hli or hld increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_A_r16mem(self: *CPU) void {
    const r16mem: u2 = @intCast((self.opcode >> 4) & 0b11);
    const addr = self.getR16mem(r16mem);

    self.regs.A = self.bus.read(addr);
}

/// 00001000[imm16]: LD [imm16], SP: Copy SP & $FF (lower byte of SP) at address imm16 and
/// SP >> 8 (upper byte of SP) at address imm16 + 1.
///
/// Cycles: 5
/// Bytes: 3
fn LD_imm16_SP(self: *CPU) void {
    const imm16 = self.getImm16();
    self.bus.write(imm16, @intCast(self.regs.SP & 0xFF));
    self.bus.write(imm16 + 1, @intCast(self.regs.SP >> 8));
}

/// 00[r16]0011: INC r16: Increment the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn INC_r16(self: *CPU) void {
    self.internalCycle(); // 16-bit arithmetic takes consumes an M-cycle
    const r16: u2 = @intCast((self.opcode >> 4) & 0b11);
    const new_val = self.getR16(r16) +% 1;

    self.setR16(r16, new_val);
}

/// 00[r16]1011: DEC r16: Decrement the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn DEC_r16(self: *CPU) void {
    self.internalCycle();
    const r16: u2 = @intCast((self.opcode >> 4) & 0b11);
    const new_val = self.getR16(r16) -% 1;

    self.setR16(r16, new_val);
}

/// 00[r16]1001: ADD HL, r16: Add the value in r16 to HL
///
/// Cycles: 2
/// Bytes: 1
/// Flags:
///     N=0
///     H=Set if overflow from bit 11
///     C=Set if overflow from bit 15
fn ADD_HL_r16(self: *CPU) void {
    self.internalCycle();
    const r16: u2 = @intCast((self.opcode >> 4) & 0b11);
    const val = self.getR16(r16);

    const hl = self.regs.getHL();
    const new_hl, const c = @addWithOverflow(hl, val); // add with carry flag

    self.regs.setHL(new_hl); // set HL register
    self.setFlag(.N, false);
    self.setFlag(.H, ((@as(u32, hl) & 0x0FFF) + (@as(u32, val) & 0x0FFF)) > 0x0FFF);
    self.setFlag(.C, c == 1);
}

/// 00[r8]100: INC r8: Increment the value in register r8 by 1
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
fn INC_r8(self: *CPU) void {
    const r8: u3 = @intCast((self.opcode >> 3) & 0b111);
    const val = self.getR8(r8);
    const new_val = val +% 1;

    self.setR8(r8, new_val);
    self.setFlag(.Z, new_val == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, ((val & 0x0F) + (1 & 0x0F)) > 0x0F);
}

/// 00[r8]101: DEC r8: Decrement the value in register r8 by 1
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
fn DEC_r8(self: *CPU) void {
    const r8: u3 = @intCast((self.opcode >> 3) & 0b111);
    const val = self.getR8(r8);
    const new_val = val -% 1;

    self.setR8(r8, new_val);
    self.setFlag(.Z, new_val == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, (val & 0x0F) < (1 & 0x0F));
}

/// 00[r8]110[imm8]: LD r8, imm8: Copy the value imm8 into register r8
///
/// Cycles: 2
/// Bytes: 2
fn LD_r8_imm8(self: *CPU) void {
    const r8: u3 = @intCast((self.opcode >> 3) & 0b111);
    const imm8 = self.getImm8(u8);

    self.setR8(r8, imm8);
}

/// 00000111: RLCA: Rotate register A left
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=0
///     N=0
///     H=0
///     C=Set to old bit 7 of A
fn RLCA(self: *CPU) void {
    const carry = self.regs.A >> 7;

    self.regs.A = std.math.rotl(u8, self.regs.A, 1);
    self.setFlag(.Z, false);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 00001111: RRCA: Rotate register A right
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///    Z=0
///    N=0
///    H=0
///    C=Set to old bit 0 of A
fn RRCA(self: *CPU) void {
    const carry = self.regs.A & 0b1;

    self.regs.A = std.math.rotr(u8, self.regs.A, 1);
    self.setFlag(.Z, false);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 00010111: RLA: Rotate register A left, through carry flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///    Z=0
///    N=0
///    H=0
///    C=Set to old bit 7 of A
fn RLA(self: *CPU) void {
    const old_carry = @intFromBool(self.getFlag(.C));
    const new_carry = (self.regs.A >> 7) & 0b1;

    self.regs.A = (self.regs.A << 1) | old_carry;
    self.setFlag(.Z, false);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, new_carry == 1);
}

/// 00011111: RRA: Rotate register A right, through carry flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///    Z=0
///    N=0
///    H=0
///    C=Set to old bit 0 of A
fn RRA(self: *CPU) void {
    const old_carry: u8 = @intFromBool(self.getFlag(.C));
    const new_carry = self.regs.A & 0b1;

    self.regs.A = (self.regs.A >> 1) | (old_carry << 7);
    self.setFlag(.Z, false);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, new_carry == 1);
}

/// 00100111: DAA: Decimal Adjust Accumulator (register A)
/// Designed to be used after performing an arithmetic operation
/// (ADD, ADC, SUB, SBC) whose input were in Binary Coded Decimal (BCD),
/// adjusting the result to likewise be in BCD.
///
/// Exact behavior depends on subtract flag N:
///     If N=1 (after a subtraction):
///         1. Initialize the adjustment to 0.
///         2. If half-carry flag H=1, add 0x6 to the adjustment.
///         3. If carry flag C=1, add 0x60 to the adjustment.
///         4. Subtract the adjustment from register A.
///     If N=0 (after an addition):
///         1. Initialize the adjustment to 0.
///         2. If half-carry flag H=1 or the lower nibble of A (A & 0xF) > 0x9,
///             add 0x6 to the adjustment.
///         3. If carry flag C=1 or A > 0x99, add 0x60 to the adjustment and
///             set carry flag C=1.
///         4. Add the adjustment to register A.
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     H=0
///     C=Set or reset depending to operation
fn DAA(self: *CPU) void {
    var adjustment: u8 = 0;
    if (self.getFlag(.N)) {
        if (self.getFlag(.H)) {
            adjustment += 0x6;
        }
        if (self.getFlag(.C)) {
            adjustment += 0x60;
        }
        self.regs.A -%= adjustment;
    } else {
        if (self.getFlag(.H) or (self.regs.A & 0xF) > 0x9) {
            adjustment += 0x6;
        }
        if (self.getFlag(.C) or (self.regs.A) > 0x99) {
            adjustment += 0x60;
            self.setFlag(.C, true);
        }
        self.regs.A +%= adjustment;
    }

    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.H, false);
}

/// 00101111: CPL: ComPLement accumulator (A = ~A) (bitwise NOT)
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=1
///     H=1
fn CPL(self: *CPU) void {
    self.regs.A = ~self.regs.A;

    self.setFlag(.N, true);
    self.setFlag(.H, true);
}

/// 00110111: SCF: Set Carry Flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=0
///     H=0
///     C=1
fn SCF(self: *CPU) void {
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, true);
}

/// 00111111: CCF: Complement Carry Flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=0
///     H=0
///     C=Inverted
fn CCF(self: *CPU) void {
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, !self.getFlag(.C));
}

/// 00011000[imm8]: jr imm8: Relative Jump to address imm8 (PC + 1 + imm8)
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3
/// Bytes: 2
fn JR_imm8(self: *CPU) void {
    const offset = self.getImm8(i8);

    self.internalCycle();

    // cast pc and offset to i32 to perform signed addition
    const pc_i32: i32 = @intCast(self.regs.PC);
    const offset_i32: i32 = @intCast(offset);
    const result: u32 = @bitCast(pc_i32 + offset_i32);
    self.regs.PC = @truncate(result);
}

/// 001[cond]000[imm8]: JR cond, imm8: Relative Jump to address imm8
/// (SP + imm8) if condition cond is met.
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3 taken / 2 untaken
/// Bytes: 2
fn JR_cond_imm8(self: *CPU) void {
    const cond: u2 = @intCast((self.opcode >> 3) & 0b11);
    if (self.checkCondition(cond)) {
        self.JR_imm8();
    } else {
        _ = self.getImm8(u8); // skip imm8
    }
}

/// 00010000: STOP: What happens depends on the state of the emulator. Refer to
/// this picture for details: https://gbdev.io/pandocs/imgs/stop_diagram.svg
///
/// Cycles: -
/// Bytes: 2 (depends on emulator state)
fn STOP(self: *const CPU) void {
    _ = self;
    @panic("not implemented");
}

// ------------------------------- end block 0 --------------------------------
// ---------------- block 1: 8-bit register-to-register loads -----------------

/// 01[dest(r8)][src(r8)]: LD r8, r8: Copy value from src(r8) to dest(r8)
/// Storing a register into itself is a no-op. trying to encode LD [hl], [hl]
/// yields the halt instruction
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
fn LD_r8_r8(self: *CPU) void {
    const src: u3 = @intCast(self.opcode & 0b111);
    const dest: u3 = @intCast((self.opcode >> 3) & 0b111);

    const value = self.getR8(src);

    self.setR8(dest, value);
}

/// 01110110: HALT (LD [HL], [HL]): Enter CPU low-power mode until an interrupt
/// occurs. Exact behavior depends on IME flag, and whether interrupts are
/// pending (i.e. whether [IE] & [IF] != 0).
///
/// If IME=1:
///     CPU enters low-power mode until after an interrupt is about to be
///     serviced. The handler is executed normally, and the CPU resumes
///     execution after the HALT when that returns.
/// If IME=0, and no interrupts are pending:
///     As soon as an interrupt becomes pending, the CPU resumes execution.
///     This is like the above, except that the handler is not called.
/// If IME=0, and interrupts are pending:
///     CPU continues execution after the HALT, but the byte after it is read
///     twice in a row (PC is not incremented, due to hardware bug).
///
/// Cycles: -
/// Bytes: 1
fn HALT(self: *CPU) void {
    if (self.IME) {
        self.halted = true;
    } else {
        const IE = self.bus.getIE();
        const IF = self.bus.getIF();
        if ((IE & IF) == 0) {
            self.halted = true;
        } else {
            self.HALT_bug = true;
        }
    }
}

// ------------------------------- end block 1 --------------------------------
// ------------------------ block 2: 8-bit arithmetic -------------------------

/// 10000[r8]: ADD A, r8: Add the value in r8 to register A
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADD_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);
    const old_a = self.regs.A;

    self.regs.A, const c = @addWithOverflow(old_a, value);
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, ((old_a & 0x0F) + (value & 0x0F)) > 0x0F);
    self.setFlag(.C, c == 1);
}

/// 10001[r8]: ADC A, r8: Add the value in r8 and the carry flag to register A
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADC_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);
    const carry = @intFromBool(self.getFlag(.C));
    const old_a = self.regs.A;

    const sum = @as(u9, old_a) + value + carry;

    self.regs.A = @truncate(sum); // wrap back to u8
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, ((old_a & 0x0F) + (value & 0x0F) + carry) > 0x0F);
    self.setFlag(.C, sum > 0xFF);
}

/// 10010[r8]: SUB A, r8: Subtract the value in r8 from register A
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if r8 > A)
fn SUB_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);
    const old_a = self.regs.A;

    self.regs.A, const c = @subWithOverflow(old_a, value);
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, (old_a & 0x0F) < (value & 0x0F));
    self.setFlag(.C, c == 1);
}

/// 10011[r8]: SBC A, r8: Subtract the value in r8 and the carry flag from
/// register A
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if (r8 + C) > A)
fn SBC_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);
    const carry = @intFromBool(self.getFlag(.C));
    const old_a = self.regs.A;

    const sum = @as(i16, old_a) - value - carry;
    const half_check = (@as(i16, old_a) & 0xF) - (value & 0xF) - carry;

    self.regs.A = @truncate(@as(u16, @bitCast(sum))); // wrap back to u8
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, half_check < 0);
    self.setFlag(.C, sum < 0);
}

/// 10100[r8]: AND A, r8: A = A & val(r8) (bitwise AND)
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=1
///     C=0
fn AND_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);

    self.regs.A = self.regs.A & value;
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, true);
    self.setFlag(.C, false);
}

/// 10101[r8]: XOR A, r8: A = A ^ val(r8) (bitwise XOR)
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn XOR_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);

    self.regs.A = self.regs.A ^ value;
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, false);
}

/// 10110[r8]: OR A, r8: A = A | val(r8) (bitwise OR)
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn OR_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);

    self.regs.A = self.regs.A | value;
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, false);
}

/// 10111[r8]: CP A, r8: ComPare value in register A with value in r8.
/// This subtracts r8 from A and sets flags accordingly, but discards the
/// result.
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if r8 > A)
fn CP_A_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const value = self.getR8(r8);
    const old_a = self.regs.A;

    const res, const c = @subWithOverflow(old_a, value);
    self.setFlag(.Z, res == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, (old_a & 0x0F) < (value & 0x0F));
    self.setFlag(.C, c == 1);
}

// ------------------------------- end block 2 --------------------------------
// --------------------------------- block 3 ----------------------------------

/// 11000110[imm8]: ADD A, imm8: Add value imm8 to register A
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADD_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const old_a = self.regs.A;

    self.regs.A, const c = @addWithOverflow(old_a, imm8);
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, ((old_a & 0x0F) + (imm8 & 0x0F)) > 0x0F);
    self.setFlag(.C, c == 1);
}

/// 11001110[imm8]: ADC A, imm8: Add value imm8 plus the carry flag to
/// register A
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADC_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const carry = @intFromBool(self.getFlag(.C));
    const old_a = self.regs.A;

    const sum = @as(u9, old_a) + imm8 + carry;

    self.regs.A = @truncate(sum); // wrap back to u8
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, ((old_a & 0x0F) + (imm8 & 0x0F) + carry) > 0x0F);
    self.setFlag(.C, sum > 0xFF);
}

/// 11010110[imm8]: SUB A, imm8: Subtract value imm8 from register A
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if imm8 > A)
fn SUB_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const old_a = self.regs.A;

    self.regs.A, const c = @subWithOverflow(old_a, imm8);
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, (old_a & 0x0F) < (imm8 & 0x0F));
    self.setFlag(.C, c == 1);
}

/// 11011110[imm8]: SBC A, imm8: Subtract value imm8 and the carry flag from
/// register A
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if (imm8 + C) > A)
fn SBC_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const carry = @intFromBool(self.getFlag(.C));
    const old_a = self.regs.A;

    const sum = @as(i16, old_a) - imm8 - carry;
    const half_check = (@as(i16, old_a) & 0xF) - (imm8 & 0xF) - carry;

    self.regs.A = @truncate(@as(u16, @bitCast(sum))); // wrap back to u8
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, half_check < 0);
    self.setFlag(.C, sum < 0);
}

/// 11100110[imm8]: AND A, imm8: A = A & imm8 (bitwise AND)
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=1
///     C=0
fn AND_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);

    self.regs.A = self.regs.A & imm8;
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, true);
    self.setFlag(.C, false);
}

/// 11101110[imm8]: XOR A, imm8: A = A ^ imm8 (bitwise XOR)
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn XOR_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);

    self.regs.A = self.regs.A ^ imm8;
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, false);
}

/// 11110110[imm8]: OR A, imm8: A = A | imm8 (bitwise OR)
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn OR_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    self.regs.A = self.regs.A | imm8;
    self.setFlag(.Z, self.regs.A == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, false);
}

/// 11111110[imm8]: CP A, imm8: ComPare value in register A with value imm8.
/// This subtracts imm8 from A and sets flags accordingly, but discards the
/// result.
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if imm8 > A)
fn CP_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const old_a = self.regs.A;

    const res, const c = @subWithOverflow(old_a, imm8);
    self.setFlag(.Z, res == 0);
    self.setFlag(.N, true);
    self.setFlag(.H, (old_a & 0x0F) < (imm8 & 0x0F));
    self.setFlag(.C, c == 1);
}

/// 11001001: RET: Return from subroutine. This is basically a POP PC.
///
/// Cycles: 4
/// Bytes: 1
fn RET(self: *CPU) void {
    const target = self.pop();
    self.internalCycle();
    self.regs.PC = target;
}

/// 110[cond]000: RET cond: Return from subroutine if condition cond is met.
///
/// Cycles: 5 taken / 2 untaken
/// Bytes: 1
fn RET_cond(self: *CPU) void {
    const cond: u2 = @intCast((self.opcode >> 3) & 0b11);

    self.internalCycle(); // decision cycle
    if (self.checkCondition(cond)) {
        self.RET();
    }
}

/// 11011001: RETI: Return from interrupt and enable interrupts. This is
/// basically a POP PC followed by setting the IME flag to 1
/// (EI followed by RET).
///
/// Cycles: 4
/// Bytes: 1
fn RETI(self: *CPU) void {
    self.RET();
    self.IME = true;
}

/// 11000011[imm16]: JP imm16: Jump to address imm16 (copy n16 into PC).
///
/// Cycles: 4
/// Bytes: 3
fn JP_imm16(self: *CPU) void {
    const target = self.getImm16();

    self.internalCycle();
    self.regs.PC = target;
}

/// 110[cond]010[imm16]: JP cond, imm16: Jump to address imm16 if condition
/// cond is met.
///
/// Cycles: 4 taken / 3 untaken
/// Bytes: 3
fn JP_cond_imm16(self: *CPU) void {
    const cond: u2 = @intCast((self.opcode >> 3) & 0b11);

    if (self.checkCondition(cond)) {
        self.JP_imm16();
    } else {
        _ = self.getImm16(); // skip imm16
    }
}

/// 11101001: JP HL: Jump to address in HL (copy HL into PC).
///
/// Cycles: 1
/// Bytes: 1
fn JP_HL(self: *CPU) void {
    self.regs.PC = self.regs.getHL();
}

/// 11001101[imm16]: CALL imm16: Call address imm16. This pushes the address
/// of the instruction after the CALL on the stack, such that RET can pop it
/// later; then, it executes an implicit JP imm16
///
/// Cycles: 6
/// Bytes: 3
fn CALL_imm16(self: *CPU) void {
    const target = self.getImm16();

    self.push(self.regs.PC);

    self.regs.PC = target;
}

/// 110[cond]100: CALL cond, imm16: Call address imm16 if condition cond is met
///
/// Cycles: 6 taken / 3 untaken
/// Bytes: 3
fn CALL_cond_imm16(self: *CPU) void {
    const cond: u2 = @intCast((self.opcode >> 3) & 0b11);

    if (self.checkCondition(cond)) {
        self.CALL_imm16();
    } else {
        _ = self.getImm16(); // skip imm16
    }
}

/// 11[tgt3]111: RST tgt3: Call to address tgt3*8
///
/// Cycles: 4
/// Bytes: 1
fn RST_tgt3(self: *CPU) void {
    const tgt3 = (self.opcode >> 3) & 0b111;

    self.push(self.regs.PC);
    self.regs.PC = tgt3 * 8;
}

/// 11[r16stk]0001: POP r16stk: Pop register r16stk off the stack
///
/// Cycles: 3
/// Bytes: 1
fn POP_r16stk(self: *CPU) void {
    const value = self.pop();
    const r16stk: u2 = @intCast((self.opcode >> 4) & 0b11);

    self.setR16stk(r16stk, value);
}

/// 11[r16stk]0101: PUSH r16stk: Push register r16stk onto the stack
///
/// Cycles: 4
/// Bytes: 1
fn PUSH_r16stk(self: *CPU) void {
    const r16stk: u2 = @intCast((self.opcode >> 4) & 0b11);
    const value = self.getR16stk(r16stk);

    self.push(value);
}

/// 11100010: LDH [c], A: Store value of register A into byte at address
/// $FF00 + C
///
/// Cycles: 2
/// Bytes: 1
fn LDH_C_A(self: CPU) void {
    const address = 0xFF00 + @as(u16, self.regs.C);

    self.bus.write(address, self.regs.A);
}

/// TRUTH UNKNOWN
/// 11100000[imm8]: LDH [imm8], A: Store value of register A into byte at
/// address $FF00 + imm8
///
/// Cycles: 3
/// Bytes: 2
fn LDH_imm8_A(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const address = 0xFF00 + @as(u16, imm8);

    self.bus.write(address, self.regs.A);
}

/// 11101010[imm16]: LD [imm16], A: Copy the value of register A into the byte
/// at address imm16
///
/// Cycles: 4
/// Bytes: 3
fn LD_imm16_A(self: *CPU) void {
    const address = self.getImm16();

    self.bus.write(address, self.regs.A);
}

/// 11110010: LDH A, [c]: Copy the byte at address $FF00 + C into register A
///
/// Cycles: 2
/// Bytes: 1
fn LDH_A_C(self: *CPU) void {
    const address = 0xFF00 + @as(u16, self.regs.C);

    self.regs.A = self.bus.read(address);
}

/// TRUTH UNKNOWN
/// 11110000[imm8]: LDH A, [imm8]: Copy the byte at address $FF00 + imm8
/// into register A
///
/// Cycles: 3
/// Bytes: 2
fn LDH_A_imm8(self: *CPU) void {
    const imm8 = self.getImm8(u8);
    const address = 0xFF00 + @as(u16, imm8);

    self.regs.A = self.bus.read(address);
}

/// 11111010[imm16]: LD A, [imm16]: Load value at address imm16 into register A
///
/// Cycles: 4
/// Bytes: 3
fn LD_A_imm16(self: *CPU) void {
    const address = self.getImm16();

    self.regs.A = self.bus.read(address);
}

/// 11101000[imm8]: ADD SP, imm8: Add signed value imm8 to stack pointer SP
///
/// Cycles: 4
/// Bytes: 2
/// Flags:
///     Z=0
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADD_SP_imm8(self: *CPU) void {
    const offset = self.getImm8(i8);
    const old_sp = self.regs.SP;
    const offset_bits: u8 = @bitCast(offset);

    self.internalCycle();
    self.internalCycle();
    // cast sp and offset to i32 to perform signed addition
    const sp_i32: i32 = @intCast(old_sp);
    const offset_i32: i32 = @intCast(offset);
    const result: u32 = @bitCast(sp_i32 +% offset_i32);
    self.regs.SP = @truncate(result);

    const h_check = (old_sp & 0xF) + (offset_bits & 0xF);
    const c_check = (old_sp & 0xFF) + offset_bits;
    self.setFlag(.Z, false);
    self.setFlag(.N, false);
    self.setFlag(.H, h_check > 0xF);
    self.setFlag(.C, c_check > 0xFF);
}

/// 11111000[imm8]: LD HL, SP+imm8: Add signed value imm8 to stack pointer SP
/// and store result in HL
///
/// Cycles: 3
/// Bytes: 2
/// Flags:
///     Z=0
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn LD_HL_SPimm8(self: *CPU) void {
    const offset = self.getImm8(i8);
    const old_sp = self.regs.SP;
    const offset_bits: u8 = @bitCast(offset);

    self.internalCycle();
    // cast sp and offset to i32 to perform signed addition
    const sp_i32: i32 = @intCast(old_sp);
    const offset_i32: i32 = @intCast(offset);
    const result: u32 = @bitCast(sp_i32 +% offset_i32);
    self.regs.setHL(@truncate(result));

    const h_check = (old_sp & 0xF) + (offset_bits & 0xF);
    const c_check = (old_sp & 0xFF) + offset_bits;
    self.setFlag(.Z, false);
    self.setFlag(.N, false);
    self.setFlag(.H, h_check > 0xF);
    self.setFlag(.C, c_check > 0xFF);
}

/// 11111001: LD A, HL: Copy register HL into stack pointer SP
///
/// Cycles: 2
/// Bytes: 1
fn LD_SP_HL(self: *CPU) void {
    self.internalCycle();
    self.regs.SP = self.regs.getHL();
}

/// 11111011: EI: Enable Interrupts (IME = 1)
/// The flag is only set after the instruction following EI
///
/// Cycles: 1
/// Bytes: 1
fn EI(self: *CPU) void {
    self.IME_scheduled = true;
}

/// 11110011: DI: Disable Interrupts (IME = 0)
///
/// Cycles: 1
/// Bytes: 1
fn DI(self: *CPU) void {
    self.IME = false;
}

// ------------------------------- end block 3 --------------------------------
// -------------------------- block 4: Opcode holes ---------------------------

/// these opcodes are not implemented and hard-lock the CPU until the console
/// is powered off: $D3, $DB, $DD, $E3, $E4, $EB, $EC, $ED, $F4, $FC,
/// and $FD

// ------------------------------- end block 4 --------------------------------
// ------------------------ block 5: CB prefix opcodes ------------------------

/// $CB prefix. The next executed instruction is from the $CB bank portion of
/// the decode ROM. $CB prefix opcodes behave like two-byte opcodes
fn CB_prefix(self: *CPU) void {
    self.opcode = self.fetch();

    switch (self.opcode >> 6) {
        1 => self.BIT_b3_r8(),
        2 => self.RES_b3_r8(),
        3 => self.SET_b3_r8(),
        else => {
            switch (self.opcode >> 3) {
                0 => self.RLC_r8(),
                1 => self.RRC_r8(),
                2 => self.RL_r8(),
                3 => self.RR_r8(),
                4 => self.SLA_r8(),
                5 => self.SRA_r8(),
                6 => self.SWAP_r8(),
                7 => self.SRL_r8(),
                else => unreachable,
            }
        },
    }
}

/// 00000[r8]: RLC r8: Rotate register r8 left. Old bit 7 to carry flag
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 7 of r8
fn RLC_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const carry = value >> 7;

    value = std.math.rotl(u8, value, 1);

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 00001[r8]: RRC r8: Rotate register r8 right. Old bit 0 to carry flag
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn RRC_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const carry = value & 0b1;

    value = std.math.rotr(u8, value, 1);

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 00010[r8]: RL r8: Rotate register r8 left, through carry flag
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 7 of r8
fn RL_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const old_carry = @intFromBool(self.getFlag(.C));
    const new_carry = (value >> 7) & 0b1;

    value = (value << 1) | old_carry;

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, new_carry == 1);
}

/// 00011[r8]: RR r8: Rotate register r8 right, through carry flag
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn RR_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const old_carry: u8 = @intFromBool(self.getFlag(.C));
    const new_carry = value & 0b1;

    value = (value >> 1) | (old_carry << 7);

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, new_carry == 1);
}

/// 00100[r8]: SLA r8: Shift Left Arithmetically register r8 left into carry
/// bit 0 of r8 set to 0
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 7 of r8
fn SLA_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const carry = value >> 7;

    value <<= 1;

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 00101[r8]: SRA r8: Shift Right Arithmetically register r8 right into carry
/// bit 7 of r8 does not change
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn SRA_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const carry = value & 0b1;
    const bit7 = value & 0b10000000;

    value >>= 1;
    value |= bit7;

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 00110[r8]: SWAP r8: Swap upper & lower 4 bits of register r8
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn SWAP_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const high = value >> 4;
    const low = value & 0xF;

    value = (low << 4) | high;

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, false);
}

/// 00111[r8]: SRL r8: Shift Right Logically register r8 right into carry
/// bit 7 of r8 set to 0
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn SRL_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    var value = self.getR8(r8);
    const carry = value & 0b1;

    value >>= 1;

    self.setR8(r8, value);
    self.setFlag(.Z, value == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, false);
    self.setFlag(.C, carry == 1);
}

/// 01[b3][r8]: BIT b3, r8: Test bit b3 in register r8, set zero flag if bit
/// not set
///
/// Cycles: 2 or 3 if (HL)
/// Bytes: 2
/// Flags:
///     Z=Set if bit b3 is 0
///     N=0
///     H=1
fn BIT_b3_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const b3: u3 = @intCast((self.opcode >> 3) & 0b111);
    const value = self.getR8(r8);

    const bit = (value >> b3) & 0b1;

    self.setFlag(.Z, bit == 0);
    self.setFlag(.N, false);
    self.setFlag(.H, true);
}

/// 10[b3][r8]: RES b3, r8: Set bit b3 in register r8 to 0. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
fn RES_b3_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const b3: u3 = @intCast((self.opcode >> 3) & 0b111);
    var value = self.getR8(r8);

    value &= (@as(u8, 1) << b3) ^ 0xFF;

    self.setR8(r8, value);
}

/// 11[b3][r8]: SET b3, r8: Set bit b3 in register r8 to 1. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
fn SET_b3_r8(self: *CPU) void {
    const r8: u3 = @intCast(self.opcode & 0b111);
    const b3: u3 = @intCast((self.opcode >> 3) & 0b111);
    var value = self.getR8(r8);

    value |= @as(u8, 1) << b3;

    self.setR8(r8, value);
}

const Timer = @import("Timer.zig");
test "NOP" {
    // setup fake RAM
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    try cpu.step();
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "LD_r16_imm16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b00000001; // Opcode for LD BC, imm16
    bus.ROM_0[1] = 0x34; // Low byte
    bus.ROM_0[2] = 0x12; // High byte
    try cpu.step();
    try std.testing.expectEqual(0x12, cpu.regs.B); // Low byte
    try std.testing.expectEqual(0x34, cpu.regs.C); // High byte
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);

    bus.ROM_0[3] = 0b00110001; // Opcode for LD SP, imm16
    bus.ROM_0[4] = 0x56; // Low byte
    bus.ROM_0[5] = 0x78; // High byte
    try cpu.step();
    try std.testing.expectEqual(0x7856, cpu.regs.SP);
    try std.testing.expectEqual(6, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "LD_r16mem_A" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0xAB; // A register
    bus.ROM_0[0] = 0b00000010; // Opcode for LD (BC), A
    cpu.regs.B = 0x34; // B register (high byte of BC)
    cpu.regs.C = 0x12; // C register (low byte of BC)
    try cpu.step();
    try std.testing.expectEqual(0xAB, bus.ROM_0[0x3412]);
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[1] = 0b00100010; // Opcode for LD (DE), A
    cpu.regs.H = 0x56; // H register (high byte of HL)
    cpu.regs.L = 0xFF; // L register (low byte of HL)
    try cpu.step();
    try std.testing.expectEqual(0xAB, bus.ROM_S[0x16FF]);
    try std.testing.expectEqual(0x57, cpu.regs.H);
    try std.testing.expectEqual(0x00, cpu.regs.L);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);

    bus.ROM_0[2] = 0b00110010; // Opcode for LD (HLD), A
    cpu.regs.H = 0x4A; // H register (high byte of HL)
    cpu.regs.L = 0xBC; // L register (low byte of HL)
    try cpu.step();
    try std.testing.expectEqual(0xAB, bus.ROM_S[0x0ABC]);
    try std.testing.expectEqual(0x4A, cpu.regs.H);
    try std.testing.expectEqual(0xBB, cpu.regs.L);
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "LD_A_r16mem" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0x3412] = 0xCD;
    bus.ROM_0[0] = 0b00001010; // Opcode for LD A, (BC)
    cpu.regs.B = 0x34; // B register (high byte of BC)
    cpu.regs.C = 0x12; // C register (low byte of BC)
    try cpu.step();
    try std.testing.expectEqual(0xCD, cpu.regs.A); // A register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "LD_imm16_SP" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.SP = 0x9ABC;
    bus.ROM_0[0] = 0b00001000; // Opcode for LD (imm16), SP
    bus.ROM_0[1] = 0x10; // Low byte of imm16
    bus.ROM_0[2] = 0x80; // High byte of
    try cpu.step();
    try std.testing.expectEqual(0xBC, bus.VRAM[0x0010]); // Low byte of SP
    try std.testing.expectEqual(0x9A, bus.VRAM[0x0011]); // High byte of SP
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(20, timer.counter);
}

test "INC_r16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0xFF; // B register
    cpu.regs.C = 0xFF; // C register
    bus.ROM_0[0] = 0b00000011; // Opcode for INC BC
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.B); // B register
    try std.testing.expectEqual(0x00, cpu.regs.C); // C register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.SP = 0x1234; // SP
    bus.ROM_0[1] = 0b00110011; // Opcode for INC SP
    try cpu.step();
    try std.testing.expectEqual(0x1235, cpu.regs.SP); // SP
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "DEC_r16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0x00; // B register
    cpu.regs.C = 0x00; // C register
    bus.ROM_0[0] = 0b00001011; // Opcode for DEC BC
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.B); // B register
    try std.testing.expectEqual(0xFF, cpu.regs.C); // C register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.SP = 0x0000; // SP
    bus.ROM_0[1] = 0b00111011; // Opcode for DEC SP
    try cpu.step();
    try std.testing.expectEqual(0xFFFF, cpu.regs.SP); // SP
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "ADD_HL_r16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.H = 0x1F; // H register
    cpu.regs.L = 0x34; // L register
    cpu.regs.B = 0x01; // B register
    cpu.regs.C = 0x10; // C register
    bus.ROM_0[0] = 0b00001001; // Opcode for ADD HL, BC
    try cpu.step();
    try std.testing.expectEqual(0x20, cpu.regs.H);
    try std.testing.expectEqual(0x44, cpu.regs.L);
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.F = 0b10100000;
    cpu.regs.H = 0xFF; // H register
    cpu.regs.L = 0xFF; // L register
    cpu.regs.D = 0x00; // D register
    cpu.regs.E = 0x01; // E register
    bus.ROM_0[1] = 0b00011001; // Opcode for ADD HL, DE
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.H);
    try std.testing.expectEqual(0x00, cpu.regs.L);
    try std.testing.expectEqual(0b10110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "INC_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0xFF; // A register
    bus.ROM_0[0] = 0b00111100; // Opcode for INC A
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.A); // A register
    try std.testing.expectEqual(0b10100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "DEC_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x00; // A register
    bus.ROM_0[0] = 0b00111101; // Opcode for DEC A
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "LD_r8_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b00000110; // Opcode for LD B, imm8
    bus.ROM_0[1] = 0x7A; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x7A, cpu.regs.B); // B register
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "RLCA" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b10000001; // A register
    bus.ROM_0[0] = 0b00000111; // Opcode for RLCA
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "RRCA" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b00000011; // A register
    bus.ROM_0[0] = 0b00001111; // Opcode for RRCA
    try cpu.step();
    try std.testing.expectEqual(0b10000001, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "RLA" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b10000001; // A register
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b00010111; // Opcode for RLA
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "RRA" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b00000011; // A register
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b00011111; // Opcode for RRA
    try cpu.step();
    try std.testing.expectEqual(0b10000001, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "DAA" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x98; // A register
    cpu.regs.F = 0b01110000; // Clear all flags
    bus.ROM_0[0] = 0b00100111; // Opcode for DAA
    try cpu.step();
    try std.testing.expectEqual(0x98 - 0x66, cpu.regs.A);
    try std.testing.expectEqual(0b01010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    cpu.regs.A = 0x12; // A register
    cpu.regs.F = 0b00110000; // Set N flag
    bus.ROM_0[1] = 0b00100111; // Opcode for DAA
    try cpu.step();
    try std.testing.expectEqual(0x12 + 0x66, cpu.regs.A);
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "CPL" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b10101010; // A register
    bus.ROM_0[0] = 0b00101111; // Opcode for CPL
    try cpu.step();
    try std.testing.expectEqual(0b01010101, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "SCF" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.F = 0b00000000; // Clear all flags
    bus.ROM_0[0] = 0b00110111; // Opcode for SCF
    try cpu.step();
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "CCF" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b00111111; // Opcode for CCF
    try cpu.step();
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    bus.ROM_0[1] = 0b00111111; // Opcode for CCF
    try cpu.step();
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "JR_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b00011000; // Opcode for JR imm8
    bus.ROM_0[1] = 0x05; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x07, cpu.regs.PC); // PC should be 0 + 2 + 5
    try std.testing.expectEqual(12, timer.counter);

    bus.ROM_0[8] = @bitCast(@as(i8, -2)); // imm8 value to jump back
    bus.ROM_0[7] = 0b00011000; // Opcode for JR imm8
    try cpu.step();
    try std.testing.expectEqual(0x07, cpu.regs.PC); // PC should be 7 + 2 - 2
}

test "JR_cond_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b00100000; // Opcode for JR NZ, imm8
    bus.ROM_0[1] = 0x04; // imm8 value
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x06, cpu.regs.PC); // PC should be 0 + 2 + 4
    try std.testing.expectEqual(12, timer.counter);

    bus.ROM_0[6] = 0b00100000; // Opcode for JR NZ, imm8
    bus.ROM_0[7] = 0x04; // imm8 value
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x08, cpu.regs.PC); // PC should be 6 + 2
    try std.testing.expectEqual(20, timer.counter);
}

// test "STOP" {
//     var bus = Bus.init();
// var cpu = CPU.init(&bus);
// var timer = Timer.init(&bus);
// bus.timer = &timer;
//     bus.write(0, 0b00010000); // Opcode for HALT
//     try cpu.execute();
//     try std.testing.expectEqual(1, cpu.regs.PC);
// }

test "LD_r8_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0x56;
    bus.ROM_0[0] = 0b01000000; // Opcode for LD B, B
    try cpu.step();
    try std.testing.expectEqual(0x56, cpu.regs.B); // B register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    cpu.regs.C = 0x78;
    bus.ROM_0[1] = 0b01000001; // Opcode for LD B, C
    try cpu.step();
    try std.testing.expectEqual(0x78, cpu.regs.B); // B register
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    cpu.regs.D = 0x9A;
    bus.ROM_0[2] = 0b01110010; // Opcode for LD [HL], D
    cpu.regs.H = 0x12;
    cpu.regs.L = 0x34;
    try cpu.step();
    try std.testing.expectEqual(0x9A, bus.ROM_0[0x1234]); // Memory at HL
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "HALT" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b01110110; // Opcode for HALT
    try cpu.execute();
    try std.testing.expectEqual(true, cpu.halted);
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "ADD_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x14;
    cpu.regs.B = 0x28;
    bus.ROM_0[0] = 0b10000000; // Opcode for ADD A, B
    try cpu.step();
    try std.testing.expectEqual(0x3C, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    bus.ROM_0[1] = 0b10000110; // Opcode for ADD [HL], B
    cpu.regs.H = 0x00;
    cpu.regs.L = 0x10;
    bus.ROM_0[0x0010] = 0x28;
    try cpu.step();
    try std.testing.expectEqual(0x64, cpu.regs.A);
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);
}

test "ADC_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x14;
    cpu.regs.B = 0x28;
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b10001000; // Opcode for ADC A, B
    try cpu.step();
    try std.testing.expectEqual(0x3D, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    bus.ROM_0[1] = 0b10001000; // Opcode for ADC A, B
    cpu.regs.B = 0xC2;
    cpu.regs.F = 0b00110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0x00, cpu.regs.A);
    try std.testing.expectEqual(0b10110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "SUB_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x50;
    cpu.regs.B = 0x20;
    bus.ROM_0[0] = 0b10010000; // Opcode for SUB A, B
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A);
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    bus.ROM_0[1] = 0b10010000; // Opcode for SUB A, B
    cpu.regs.B = 0x01;
    try cpu.step();
    try std.testing.expectEqual(0x2F, cpu.regs.A);
    try std.testing.expectEqual(0b01100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "SBC_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x50;
    cpu.regs.B = 0x20;
    bus.ROM_0[0] = 0b10011000; // Opcode for SBC A, B
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    bus.ROM_0[1] = 0b10011000; // Opcode for SBC A, B
    cpu.regs.B = 0x30;
    cpu.regs.F = 0b01110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "AND_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b11001100;
    cpu.regs.B = 0b10101010;
    bus.ROM_0[0] = 0b10100000; // Opcode for AND A, B
    try cpu.step();
    try std.testing.expectEqual(0b10001000, cpu.regs.A);
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "XOR_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b11001100;
    cpu.regs.B = 0b10101010;
    bus.ROM_0[0] = 0b10101000; // Opcode for XOR A, B
    try cpu.step();
    try std.testing.expectEqual(0b01100110, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "OR_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b11001100;
    cpu.regs.B = 0b10101010;
    bus.ROM_0[0] = 0b10110000; // Opcode for OR A, B
    try cpu.step();
    try std.testing.expectEqual(0b11101110, cpu.regs.A);
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "CP_A_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x50;
    cpu.regs.B = 0x20;
    bus.ROM_0[0] = 0b10111000; // Opcode for CP A, B
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    bus.ROM_0[1] = 0b10111000; // Opcode for CP A, B
    cpu.regs.B = 0x60;
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "ADD_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x10;
    bus.ROM_0[0] = 0b11000110; // Opcode for ADD A, imm8
    bus.ROM_0[1] = 0x22; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x32, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[2] = 0b11000110; // Opcode for ADD A, imm8
    bus.ROM_0[3] = 0xD0; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x02, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "ADC_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x10;
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b11001110; // Opcode for ADC A, imm8
    bus.ROM_0[1] = 0x22; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x33, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[2] = 0b11001110; // Opcode for ADC A, imm8
    bus.ROM_0[3] = 0xD0; // imm8 value
    cpu.regs.F = 0b00110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0x04, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "SUB_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x50;
    bus.ROM_0[0] = 0b11010110; // Opcode for SUB A, imm8
    bus.ROM_0[1] = 0x20; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[2] = 0b11010110; // Opcode for SUB A, imm8
    bus.ROM_0[3] = 0x31; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0xFF, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "SBC_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x50;
    bus.ROM_0[0] = 0b11011110; // Opcode for SBC A, imm8
    bus.ROM_0[1] = 0x20; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x30, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[2] = 0b11011110; // Opcode for SBC A, imm8
    bus.ROM_0[3] = 0x31; // imm8 value
    cpu.regs.F = 0b01110000; // Set Carry flag
    try cpu.step();
    try std.testing.expectEqual(0xFE, cpu.regs.A); // A register
    try std.testing.expectEqual(0b01110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "AND_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b11001100;
    bus.ROM_0[0] = 0b11100110; // Opcode for AND A, imm8
    bus.ROM_0[1] = 0b10101010; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0b10001000, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00100000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "XOR_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b11001100;
    bus.ROM_0[0] = 0b11101110; // Opcode for XOR A, imm8
    bus.ROM_0[1] = 0b10101010; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0b01100110, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "OR_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0b11001100;
    bus.ROM_0[0] = 0b11110110; // Opcode for OR A, imm8
    bus.ROM_0[1] = 0b10101010; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0b11101110, cpu.regs.A); // A register
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "CP_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x50;
    bus.ROM_0[0] = 0b11111110; // Opcode for CP A, imm8
    bus.ROM_0[1] = 0x20; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[2] = 0b11111110; // Opcode for CP A, imm8
    bus.ROM_0[3] = 0x60; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x50, cpu.regs.A); // A register unchanged
    try std.testing.expectEqual(0b01010000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "RET" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xDFFE;
    bus.ROM_0[0] = 0b11001001; // Opcode for RET
    bus.WRAM_S[0x0FFE] = 0x34; // Low byte of return address
    bus.WRAM_S[0x0FFF] = 0x12; // High byte of return address
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to return address
    try std.testing.expectEqual(0xE000, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(16, timer.counter);
}

test "RET_cond" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xFFFD;
    bus.ROM_0[0] = 0b11000000; // Opcode for RET NZ
    bus.HRAM[0xFFFD - 0xFF80] = 0x34; // Low byte of return address
    bus.HRAM[0xFFFE - 0xFF80] = 0x12; // High byte of return address
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to return address
    try std.testing.expectEqual(0xFFFF, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(20, timer.counter);

    // Prepare stack again
    cpu.regs.SP = 0xFFFD;
    bus.HRAM[0xFFFD - 0xFF80] = 0x78; // Low byte of return address
    bus.HRAM[0xFFFE - 0xFF80] = 0x56; // High byte of return address
    bus.ROM_0[0x1234] = 0b11000000; // Opcode for RET NZ
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x1235, cpu.regs.PC); // PC should just increment
    try std.testing.expectEqual(0xFFFD, cpu.regs.SP); // SP should remain unchanged
    try std.testing.expectEqual(28, timer.counter);
}

test "RETI" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xFFFC;
    bus.HRAM[0xFFFC - 0xFF80] = 0x34; // Low byte of return address
    bus.HRAM[0xFFFD - 0xFF80] = 0x12; // High byte of return address
    bus.ROM_0[0] = 0b11011001; // Opcode for RETI
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to return address
    try std.testing.expectEqual(0xFFFE, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(true, cpu.IME); // Interrupts should be enabled
    try std.testing.expectEqual(16, timer.counter);
}

test "JP_imm16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b11000011; // Opcode for JP imm16
    bus.ROM_0[1] = 0x12; // Low byte of address
    bus.ROM_0[2] = 0x34; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(16, timer.counter);
}

test "JP_cond_imm16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b11000010; // Opcode for JP NZ, imm16
    bus.ROM_0[1] = 0x12; // Low byte of address
    bus.ROM_0[2] = 0x34; // High byte of address
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(16, timer.counter);

    bus.ROM_0[0x3412] = 0b11000010; // Opcode for JP NZ, imm16
    bus.ROM_0[0x3413] = 0x56; // Low byte of address
    bus.ROM_0[0x3414] = 0x78; // High byte of address
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x3415, cpu.regs.PC); // PC should just increment
    try std.testing.expectEqual(28, timer.counter);
}

test "JP_HL" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.H = 0x12; // H register
    cpu.regs.L = 0x34; // L register
    bus.ROM_0[0] = 0b11101001; // Opcode for JP HL
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.PC); // PC should be set to HL value
    try std.testing.expectEqual(4, timer.counter);
}

test "CALL_imm16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xFFFE;

    bus.ROM_0[0] = 0b11001101; // Opcode for CALL imm16
    bus.ROM_0[1] = 0x12; // Low byte of address
    bus.ROM_0[2] = 0x34; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x03, bus.HRAM[0xFFFC - 0xFF80]); // Low byte of return address
    try std.testing.expectEqual(0x00, bus.HRAM[0xFFFD - 0xFF80]); // High byte of return address
    try std.testing.expectEqual(24, timer.counter);
}

test "CALL_cond_imm16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xFFFE;
    bus.ROM_0[0] = 0b11000100; // Opcode for CALL NZ, imm16
    bus.ROM_0[1] = 0x12; // Low byte of address
    bus.ROM_0[2] = 0x34; // High byte of address
    cpu.regs.F = 0b00000000; // Z flag not set
    try cpu.step();
    try std.testing.expectEqual(0x3412, cpu.regs.PC); // PC should be set to address
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x03, bus.HRAM[0xFFFC - 0xFF80]); // Low byte of return address
    try std.testing.expectEqual(0x00, bus.HRAM[0xFFFD - 0xFF80]); // High byte of return address
    try std.testing.expectEqual(24, timer.counter);

    // Prepare stack again
    cpu.regs.SP = 0xFFFE;
    bus.ROM_0[0x3412] = 0b11000100; // Opcode for CALL NZ, imm16
    bus.ROM_0[0x3413] = 0x56; // Low byte of address
    bus.ROM_0[0x3414] = 0x78; // High byte of address
    cpu.regs.F = 0b10000000; // Z flag set
    try cpu.step();
    try std.testing.expectEqual(0x3415, cpu.regs.PC); // PC should just increment
    try std.testing.expectEqual(0xFFFE, cpu.regs.SP); // SP should remain unchanged
    try std.testing.expectEqual(36, timer.counter);
}

test "RST_tgt3" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xFFFE;
    bus.ROM_0[0] = 0b11011111; // Opcode for RST $18
    try cpu.step();
    try std.testing.expectEqual(0x18, cpu.regs.PC); // PC should be set to target address
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x01, bus.HRAM[0xFFFC - 0xFF80]); // Low byte of return address
    try std.testing.expectEqual(0x00, bus.HRAM[0xFFFD - 0xFF80]); // High byte of return address
    try std.testing.expectEqual(16, timer.counter);
}

test "POP_r16stk" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    // Prepare stack
    cpu.regs.SP = 0xFFFC;
    bus.HRAM[0xFFFC - 0xFF80] = 0x34; // Low byte
    bus.HRAM[0xFFFD - 0xFF80] = 0x12; // High byte
    bus.ROM_0[0] = 0b11000001; // Opcode for POP BC
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.getR16(0)); // BC register
    try std.testing.expectEqual(0xFFFE, cpu.regs.SP); // SP should be incremented by 2
    try std.testing.expectEqual(12, timer.counter);
}

test "PUSH_r16stk" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.setR16(0, 0x1234); // BC register
    cpu.regs.SP = 0xFFFE;
    bus.ROM_0[0] = 0b11000101; // Opcode for PUSH BC
    try cpu.step();
    try std.testing.expectEqual(0xFFFC, cpu.regs.SP); // SP should be decremented by 2
    try std.testing.expectEqual(0x12, bus.HRAM[0xFFFD - 0xFF80]); // High byte
    try std.testing.expectEqual(0x34, bus.HRAM[0xFFFC - 0xFF80]); // Low byte
    try std.testing.expectEqual(16, timer.counter);
}

test "LDH_C_A" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.C = 0x80; // C register
    cpu.regs.A = 0x42; // A register
    bus.ROM_0[0] = 0b11100010; // Opcode for LDH (C), A
    try cpu.step();
    try std.testing.expectEqual(0x42, bus.HRAM[0]); // Check memory
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "LDH_imm8_A" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x37; // A register
    bus.ROM_0[0] = 0b11100000; // Opcode for LD (imm8), A
    bus.ROM_0[1] = 0x80; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x37, bus.HRAM[0]); // Check memory
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);
}

test "LD_imm16_A" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.A = 0x55; // A register
    bus.ROM_0[0] = 0b11101010; // Opcode for LD (imm16), A
    bus.ROM_0[1] = 0xC0; // Low byte of address
    bus.ROM_0[2] = 0x00; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x55, bus.ROM_0[0x00C0]); // Check memory
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "LDH_A_C" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.HRAM[0] = 0x7A; // Memory at address FF20
    cpu.regs.C = 0x80; // C register
    bus.ROM_0[0] = 0b11110010; // Opcode for LDH A, (C)
    try cpu.step();
    try std.testing.expectEqual(0x7A, cpu.regs.A); // A register
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "LDH_A_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.HRAM[0] = 0x8B; // Memory at address FF30
    bus.ROM_0[0] = 0b11110000; // Opcode for LDH A, (imm8)
    bus.ROM_0[1] = 0x80; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x8B, cpu.regs.A); // A register
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);
}

test "LD_A_imm16" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0x00C1] = 0x9C; // Memory at address C100
    bus.ROM_0[0] = 0b11111010; // Opcode for LD A, (imm16)
    bus.ROM_0[1] = 0xC1; // Low byte of address
    bus.ROM_0[2] = 0x00; // High byte of address
    try cpu.step();
    try std.testing.expectEqual(0x9C, cpu.regs.A); // A register
    try std.testing.expectEqual(3, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);
}

test "ADD_SP_imm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.SP = 0xFFF8;
    bus.ROM_0[0] = 0b11101000; // Opcode for ADD SP, imm8
    bus.ROM_0[1] = 0x08; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x0000, cpu.regs.SP); // SP should wrap around
    try std.testing.expectEqual(0b00110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(16, timer.counter);

    cpu.regs.SP = 0x0004;
    bus.ROM_0[2] = 0b11101000; // Opcode for ADD SP, imm8
    bus.ROM_0[3] = @bitCast(@as(i8, -5)); // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0xFFFF, cpu.regs.SP); // SP should be 4 - 6 = FFFF (wrap around)
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
}

test "LD_HL_SPimm8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.SP = 0xFFF8;
    bus.ROM_0[0] = 0b11111000; // Opcode for LD HL, SP+imm8
    bus.ROM_0[1] = 0x08; // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0xFFF8, cpu.regs.SP); // SP should stay the same
    try std.testing.expectEqual(0x0000, cpu.regs.getHL()); // HL should be SP + 8 = 0x0000 (wrap around)
    try std.testing.expectEqual(0b00110000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(12, timer.counter);

    cpu.regs.SP = 0x0004;
    bus.ROM_0[2] = 0b11111000; // Opcode for LD HL, SP+imm8
    bus.ROM_0[3] = @bitCast(@as(i8, -5)); // imm8 value
    try cpu.step();
    try std.testing.expectEqual(0x0004, cpu.regs.SP); // SP should stay the same
    try std.testing.expectEqual(0xFFFF, cpu.regs.getHL()); // HL should be SP - 6 = FFFF (wrap around)
    try std.testing.expectEqual(0b00000000, cpu.regs.F); // Check Flags
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "LD_SP_HL" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.H = 0x12; // H register
    cpu.regs.L = 0x34; // L register
    bus.ROM_0[0] = 0b11111001; // Opcode for LD SP, HL
    try cpu.step();
    try std.testing.expectEqual(0x1234, cpu.regs.SP); // SP should be set to HL value
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "EI" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.ROM_0[0] = 0b11111011; // Opcode for EI
    try cpu.step();
    try std.testing.expectEqual(true, cpu.IME_scheduled); // Interrupts scheduled to be enabled
    try std.testing.expectEqual(false, cpu.IME); // But not yet enabled
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);

    try cpu.step(); // Next instruction
    try std.testing.expectEqual(false, cpu.IME_scheduled); // Interrupts no longer scheduled
    try std.testing.expectEqual(true, cpu.IME); // IME set
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);
}

test "DI" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.IME = true;
    bus.ROM_0[0] = 0b11110011; // Opcode for DI
    try cpu.step();
    try std.testing.expectEqual(false, cpu.IME); // Interrupts should be disabled
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "OpcodeHole" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.write(0, 0xD3); // Invalid Opcode
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(1, 0xDB);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(2, 0xDD);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(3, 0xE3);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(4, 0xE4);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(5, 0xEB);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(6, 0xEC);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(7, 0xED);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(8, 0xF4);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(9, 0xFC);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
    bus.write(10, 0xFD);
    try std.testing.expectError(CpuError.InvalidOpcode, cpu.step());
}

// ------------------------ CB prefix tests ----------------------
test "RLC_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00000000; // Opcode for RLC B
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // set HL
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00000110; // Opcode for RLC (HL)
    try cpu.step();
    try std.testing.expectEqual(0b10000001, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "RRC_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00001000; // Opcode for RRC B
    try cpu.step();
    try std.testing.expectEqual(0b11000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00001110; // Opcode for RRC (HL)
    try cpu.step();
    try std.testing.expectEqual(0b01100000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "RL_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00010000; // Opcode for RL B
    try cpu.step();
    try std.testing.expectEqual(0b00000011, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // (HL)
    cpu.regs.F = 0b00000000; // Clear Carry flag
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00010110; // Opcode for RL (HL)
    try cpu.step();
    try std.testing.expectEqual(0b10000000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "RR_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    cpu.regs.F = 0b00010000; // Set Carry flag
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00011000; // Opcode for RR B
    try cpu.step();
    try std.testing.expectEqual(0b11000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // (HL)
    cpu.regs.F = 0b00000000; // Clear Carry flag
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00011110; // Opcode for RR (HL)
    try cpu.step();
    try std.testing.expectEqual(0b01100000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SLA_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00100000; // Opcode for SLA B
    try cpu.step();
    try std.testing.expectEqual(0b00000010, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00100110; // Opcode for SLA (HL)
    try cpu.step();
    try std.testing.expectEqual(0b10000000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SRA_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00101000; // Opcode for SRA B
    try cpu.step();
    try std.testing.expectEqual(0b11000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00101110; // Opcode for SRA (HL)
    try cpu.step();
    try std.testing.expectEqual(0b11100000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SWAP_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10110001; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00110000; // Opcode for SWAP B
    try cpu.step();
    try std.testing.expectEqual(0b00011011, cpu.regs.B);
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b10110001; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00110110; // Opcode for SWAP (HL)
    try cpu.step();
    try std.testing.expectEqual(0b00011011, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SRL_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b10000001; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b00111000; // Opcode for SRL B
    try cpu.step();
    try std.testing.expectEqual(0b01000000, cpu.regs.B);
    try std.testing.expectEqual(0b00010000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11000000; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b00111110; // Opcode for SRL (HL)
    try cpu.step();
    try std.testing.expectEqual(0b01100000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00000000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "BIT_b3_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b00001000; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b01000000; // Opcode for BIT 0, B
    try cpu.step();
    try std.testing.expectEqual(0b10100000, cpu.regs.F);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b00001000; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b01011110; // Opcode for BIT 3, (HL)
    try cpu.step();
    try std.testing.expectEqual(0b00001000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(0b00100000, cpu.regs.F);
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(20, timer.counter);
}

test "RES_b3_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b11111111; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b10000000; // Opcode for RES 0, B
    try cpu.step();
    try std.testing.expectEqual(0b11111110, cpu.regs.B);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b11111111; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b10011110; // Opcode for RES 3, (HL)
    try cpu.step();
    try std.testing.expectEqual(0b11110111, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}

test "SET_b3_r8" {
    var bus = Bus.init();
    var cpu = CPU.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    cpu.regs.B = 0b00000000; // B register
    bus.ROM_0[0] = 0b11001011; // CB Prefix
    bus.ROM_0[1] = 0b11000000; // Opcode for SET 0, B
    try cpu.step();
    try std.testing.expectEqual(0b00000001, cpu.regs.B);
    try std.testing.expectEqual(2, cpu.regs.PC);
    try std.testing.expectEqual(8, timer.counter);

    bus.ROM_0[0] = 0b00000000; // (HL)
    bus.ROM_0[2] = 0b11001011; // CB Prefix
    bus.ROM_0[3] = 0b11011110; // Opcode for SET 3, (HL)
    try cpu.step();
    try std.testing.expectEqual(0b00001000 | 0b00001000, bus.ROM_0[0]); // (HL)
    try std.testing.expectEqual(4, cpu.regs.PC);
    try std.testing.expectEqual(24, timer.counter);
}
