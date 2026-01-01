//! CPU module: implements the main CPU functionality
const CPU = @This();

const std = @import("std");
const Registers = @import("Registers.zig");

// opcode function type
const DispatchFn = *const fn (self: *CPU) void;

regs: Registers = Registers.init(), // 8x8-bit registers or 4x16-bit registers (AF, BC, DE, HL) + stack pointer + program counter
RAM: []u8, // reference to the system RAM so instructions can read/write memory
comptime dispatch_ptr_tbl: [4]DispatchFn = .{
    dispatch0,
    dispatch1,
    dispatch2,
    dispatch3,
},

pub fn init(RAM: []u8) CPU {
    return CPU{ .RAM = RAM };
}

pub fn execute(self: *CPU) void {
    self.dispatch_ptr_tbl[(self.opcode() >> 6)](self);
}

// --------------------------------- opcode dispatchers --------------------
fn dispatch0(self: *CPU) void {
    switch (self.opcode()) { // full opcode
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
            switch (self.opcode() & 0xF) { // lower 4 bits
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
fn dispatch1(self: *CPU) void {
    switch (self.opcode()) { // full opcode
        0x76 => self.HALT(),
        else => self.LD_r8_r8(),
    }
}
fn dispatch2(self: *CPU) void {
    _ = self;
}
fn dispatch3(self: *CPU) void {
    _ = self;
}

// --------------------------------- helper functions ----------------------
/// Fetches the opcode at the current PC
fn opcode(self: CPU) u8 {
    return self.RAM[self.regs.PC];
}

/// Gets flag from flags register
fn getFlag(self: CPU, flag: Registers.Flag) bool {
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
fn checkCondition(self: CPU, condition: u8) bool {
    return switch (condition) {
        0 => !self.getFlag(.Z), // NZ
        1 => self.getFlag(.Z), // Z
        2 => !self.getFlag(.C), // NC
        3 => self.getFlag(.C), // C
        else => unreachable,
    };
}

/// Gets the value of an 8-bit register
fn getR8(self: CPU, r8: u8) u8 {
    return switch (r8) {
        0 => self.regs.B,
        1 => self.regs.C,
        2 => self.regs.D,
        3 => self.regs.E,
        4 => self.regs.H,
        5 => self.regs.L,
        6 => { // read from memory pointed to by HL
            const addr = self.getR16(2); // HL
            return self.RAM[addr];
        },
        7 => self.regs.A,
        else => unreachable,
    };
}

/// Sets the value of an 8-bit register
fn setR8(self: *CPU, r8: u8, value: u8) void {
    switch (r8) {
        0 => self.regs.B = value,
        1 => self.regs.C = value,
        2 => self.regs.D = value,
        3 => self.regs.E = value,
        4 => self.regs.H = value,
        5 => self.regs.L = value,
        6 => { // write to memory pointed to by HL
            const addr = self.getR16(2); // HL
            self.RAM[addr] = value;
        },
        7 => self.regs.A = value,
        else => unreachable,
    }
}

/// Gets the value of a 16-bit register pair
fn getR16(self: CPU, r16: u8) u16 {
    return switch (r16) {
        0 => (@as(u16, self.regs.B) << 8) | self.regs.C,
        1 => (@as(u16, self.regs.D) << 8) | self.regs.E,
        2 => (@as(u16, self.regs.H) << 8) | self.regs.L,
        3 => self.regs.SP,
        else => unreachable,
    };
}

/// Sets the value of a 16-bit register pair
fn setR16(self: *CPU, r16: u8, value: u16) void {
    switch (r16) {
        0 => {
            self.regs.B = @intCast(value >> 8);
            self.regs.C = @intCast(value & 0xFF);
        },
        1 => {
            self.regs.D = @intCast(value >> 8);
            self.regs.E = @intCast(value & 0xFF);
        },
        2 => {
            self.regs.H = @intCast(value >> 8);
            self.regs.L = @intCast(value & 0xFF);
        },
        3 => {
            self.regs.SP = value;
        },
        else => unreachable,
    }
}

/// Gets the address pointed to by a 16-bit register pair, with optional
/// increment/decrement for HL.
fn getR16mem(self: *CPU, r16mem: u8) u16 {
    return switch (r16mem) {
        0, 1 => self.getR16(r16mem),
        2 => { // HLI
            const addr = self.getR16(2); // HL
            self.setR16(2, addr +% 1);
            return addr;
        },
        3 => { // HLD
            const addr = self.getR16(2); // HL
            self.setR16(2, addr -% 1);
            return addr;
        },
        else => unreachable,
    };
}

/// Fetches a 8-bit immediate value from the instruction stream
fn getImm8(self: CPU, T: type) T {
    return @bitCast(self.RAM[self.regs.PC + 1]);
}

/// Fetches a 16-bit immediate value from the instruction stream
fn getImm16(self: CPU) u16 {
    return (@as(u16, self.RAM[self.regs.PC + 1]) << 8) | self.RAM[self.regs.PC + 2];
}

// --------------------------------- end helper functions ------------------

// --------------------------------- CPU Instructions -------------------------
// --------------------------------- block 0 ----------------------------------
/// 00000000: NOP: No Operation
///
/// Cycles: 1
/// Bytes: 1
fn NOP(self: CPU) void {
    _ = self;
}

/// 00[r16]0001[imm16]: LD r16, imm16: Copy the value imm16 into register r16
///
/// Cycles: 3
/// Bytes: 3
fn LD_r16_imm16(self: *CPU) void {
    const r16 = (self.opcode() >> 4) & 0b11;
    const imm16 = self.getImm16();

    self.setR16(r16, imm16);
    self.regs.PC += 2;
}

/// 00[r16mem]0010: LD [r16mem], A: Store value of register A into memory pointed to by r16mem
/// (if hli/hld, increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_r16mem_A(self: *CPU) void {
    const r16mem = (self.opcode() >> 4) & 0b11;
    const addr = self.getR16mem(r16mem);

    self.RAM[addr] = self.regs.A;
}

/// 00[r16mem]1010: LD A, [r16mem]: Load value of memory pointed to by r16mem into register A
/// (hli or hld increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_A_r16mem(self: *CPU) void {
    const r16mem = (self.opcode() >> 4) & 0b11;
    const addr = self.getR16mem(r16mem);

    self.regs.A = self.RAM[addr];
}

/// 00001000[imm16]: LD [imm16], SP: Copy SP & $FF (lower byte of SP) at address imm16 and
/// SP >> 8 (upper byte of SP) at address imm16 + 1.
///
/// Cycles: 5
/// Bytes: 3
fn LD_imm16_SP(self: *CPU) void {
    const imm16 = self.getImm16();
    self.RAM[imm16] = @intCast(self.regs.SP & 0xFF);
    self.RAM[imm16 + 1] = @intCast(self.regs.SP >> 8);
    self.regs.PC += 2;
}

/// 00[r16]0011: INC r16: Increment the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn INC_r16(self: *CPU) void {
    const r16 = (self.opcode() >> 4) & 0b11;
    const new_val = self.getR16(r16) +% 1;

    self.setR16(r16, new_val);
}

/// 00[r16]1011: DEC r16: Decrement the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn DEC_r16(self: *CPU) void {
    const r16 = (self.opcode() >> 4) & 0b11;
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
    const r16 = (self.opcode() >> 4) & 0b11;
    const val = self.getR16(r16);

    const hl = self.getR16(2);
    const new_hl, const c: u8 = @addWithOverflow(hl, val); // add with carry flag

    self.setR16(2, new_hl); // set HL register
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
    const r8 = (self.opcode() >> 3) & 0b111;
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
    const r8 = (self.opcode() >> 3) & 0b111;
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
    const r8 = (self.opcode() >> 3) & 0b111;
    const imm8 = self.getImm8(u8);

    self.setR8(r8, imm8);
    self.regs.PC += 1;
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
    const carry = self.regs.A & 0b00000001;

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
    const imm8 = self.getImm8(i8);

    self.regs.PC += 1; // move past [imm8]
    // cast pc and offset to i32 to perform signed addition
    const pc_i32: i32 = @intCast(self.regs.PC);
    const offset_i32: i32 = @intCast(imm8);
    self.regs.PC = @intCast(pc_i32 + offset_i32);
}

/// 001[cond]000[imm8]: JR cond, imm8: Relative Jump to address imm8
/// (SP + imm8) if condition cond is met.
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3 taken / 2 untaken
/// Bytes: 2
fn JR_cond_imm8(self: *CPU) void {
    const cond = (self.opcode() >> 3) & 0b11;
    if (self.checkCondition(cond)) {
        self.JR_imm8();
    } else {
        self.regs.PC += 1; // skip imm8
    }
}

/// 00010000: STOP: What happens depends on the state of the emulator. Refer to
/// this picture for details: https://gbdev.io/pandocs/imgs/stop_diagram.svg
///
/// Cycles: -
/// Bytes: 2 (depends on emulator state)
fn STOP(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

// ------------------------------- end block 0 --------------------------------
// ---------------- block 1: 8-bit register-to-register loads -----------------

/// 01[dest(r8)][src(r8)]: LD r8, r8: Copy value from src(r8) to dest(r8)
/// Storing a register into itself is a no-op. trying to encode LD [hl], [hl]
/// yields the halt instruction
///
/// Cycles: 2
/// Bytes: 2
fn LD_r8_r8(self: *CPU) void {
    const src = self.opcode() & 0b111;
    const dest = (self.opcode() >> 3) & 0b111;
    const value = self.getR8(src);

    self.setR8(dest, value);
}

/// 01110110: HALT (LD [HL], [HL]): Enter CPU low-power mode until an interrupt
/// occurs. Exact behavior depends on IME flag, and whether interrupts are
/// pending (i.e. whether [IE] & [IF] != 0).
///
/// If IME!=0:
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
fn HALT(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

// ------------------------------- end block 1 --------------------------------
// ------------------------ block 2: 8-bit arithmetic -------------------------

/// 10000[r8]: ADD A, r8: Add the value in r8 to register A
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADD_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10001[r8]: ADC A, r8: Add the value in r8 and the carry flag to register A
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
///     C=Set if overflow from bit 7
fn ADC_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10010[r8]: SUB A, r8: Subtract the value in r8 from register A
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if r8 > A)
fn SUB_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10011[r8]: SBC A, r8: Subtract the value in r8 and the carry flag from
/// register A
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if (r8 + C) > A)
fn SBC_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10100[r8]: AND A, r8: A = A & r8 (bitwise AND)
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=1
///     C=0
fn AND_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10101[r8]: XOR A, r8: A = A ^ r8 (bitwise XOR)
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn XOR_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10110[r8]: OR A, r8: A = A | r8 (bitwise OR)
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn OR_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10111[r8]: CP A, r8: ComPare valur in register A with value in r8.
/// This subtracts r8 from A and sets flags accordingly, but discards the
/// result.
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
///     C=Set if borrow (i.e. if r8 > A)
fn CP_A_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn ADD_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn ADC_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn SUB_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn SBC_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn AND_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn XOR_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn OR_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn CP_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 110[cond]000: RET cond: Return from subroutine if condition cond is met.
///
/// Cycles: 5 taken / 2 untaken
/// Bytes: 1
fn RET_cond(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11001001: RET: Return from subroutine. This is basically a POP PC.
///
/// Cycles: 4
/// Bytes: 1
fn RET(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11011001: RETI: Return from interrupt and enable interrupts. This is
/// basically a POP PC followed by setting the IME flag to 1
/// (EI followed by RET).
///
/// Cycles: 4
/// Bytes: 1
fn RETI(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 110[cond]010[imm16]: JP cond, imm16: Jump to address imm16 if condition
/// cond is met.
///
/// Cycles: 4 taken / 3 untaken
/// Bytes: 3
fn JP_cond_imm16(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11000011[imm16]: JP imm16: Jump to address imm16 (copy n16 into PC).
///
/// Cycles: 4
/// Bytes: 3
fn JP_imm16(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11101001: JP HL: Jump to address in HL (copy HL into PC).
///
/// Cycles: 1
/// Bytes: 1
fn JP_HL(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 110[cond]100: CALL cond, imm16: Call address imm16 if condition cond is met
///
/// Cycles: 6 taken / 3 untaken
/// Bytes: 3
fn CALL_cond_imm16(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11001101[imm16]: CALL imm16: Call address imm16. This pushes the address
/// of the instruction adter the CALL on the stack, such that RET can pop it
/// later; then, it executes an implicit JP imm16
///
/// Cycles: 6
/// Bytes: 3
fn CALL_imm16(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11[tgt3]111: RST tgt3: Call to address tgt3*8
///
/// Cycles: 4
/// Bytes: 1
fn RST_tgt3(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11[r16stk]0001: POP r16stk: Pop register r16stk off the stack
///
/// Cycles: 3
/// Bytes: 1
fn POP_r16stk(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11[r16stk]0101: PUSH r16stk: Push register r16stk onto the stack
///
/// Cycles: 4
/// Bytes: 1
fn PUSH_r16stk(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// $CB prefix. The next executed instruction is from the $CB bank portion of
/// the decode ROM. $CB prefix opcodes behave like two-byte opcodes
fn CB_prefix(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11100010: LDH [c], A: Store value of register A into byte at address
/// $FF00 + C
///
/// Cycles: 2
/// Bytes: 1
fn LDH_c_A(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// TRUTH UNKNOWN
/// 11100000[imm8]: LDH [imm8], A: Store value of register A into byte at
/// address $FF00 + imm8
///
/// Cycles: 3
/// Bytes: 2
fn LDH_imm8_A(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11101010[imm16]: LD [imm16], A: Copy the value of register A into the byte
/// at address imm16
///
/// Cycles: 4
/// Bytes: 3
fn LD_imm16_A(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11110010: LDH A, [c]: Copy the byte at address $FF00 + C into register A
///
/// Cycles: 2
/// Bytes: 1
fn LDH_A_c(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// TRUTH UNKNOWN
/// 11110000[imm8]: LDH A, [imm8]: Copy the byte at address $FF00 + imm8
/// into register A
///
/// Cycles: 3
/// Bytes: 2
fn LDH_A_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11111010[imm16]: LD A, [imm16]: Load value at address imm16 into register A
///
/// Cycles: 4
/// Bytes: 3
fn LD_A_imm16(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn ADD_SP_imm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
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
fn LD_HL_SPimm8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11111001: LD A, HL: Copy register HL into stack pointer SP
///
/// Cycles: 2
/// Bytes: 1
fn LD_SP_HL(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11110011: DI: Disable Interrupts (IME = 0)
///
/// Cycles: 1
/// Bytes: 1
fn DI(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11111011: EI: Enable Interrupts (IME = 1)
/// The flag is only set after the instruction following EI
///
/// Cycles: 1
/// Bytes: 1
fn EI(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

// ------------------------------- end block 3 --------------------------------
// -------------------------- block 4: Opcode holes ---------------------------

/// these opcodes are not implemented and hard-lock the CPU until the console
/// is powered off: 0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC,
/// and 0xFD
fn Opcode_hole(self: CPU) void {
    _ = self;
    @panic("Opcode hole executed - CPU halted");
}

// ------------------------------- end block 4 --------------------------------
// ------------------------ block 5: CB prefix opcodes ------------------------

/// 00000[r8]: RLC r8: Rotate register r8 left. Old bit 7 to carry flag
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 7 of r8
fn RLC_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00001[r8]: RRC r8: Rotate register r8 right. Old bit 0 to carry flag
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn RRC_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00010[r8]: RL r8: Rotate register r8 left, through carry flag
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 7 of r8
fn RL_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00011[r8]: RR r8: Rotate register r8 right, through carry flag
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn RR_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00100[r8]: SLA r8: Shift Left Arithmetically register r8 left into carry
/// bit 0 of r8 set to 0
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 7 of r8
fn SLA_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00101[r8]: SRA r8: Shift Right Arithmetically register r8 right into carry
/// bit 7 of r8 does not change
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn SRA_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00110[r8]: SWAP r8: Swap upper & lower 4 bits of register r8
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=0
fn SWAP_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 00111[r8]: SRL r8: Shift Right Logically register r8 right into carry
/// bit 7 of r8 set to 0
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=0
///     C=Set to old bit 0 of r8
fn SRL_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 01[b3][r8]: BIT b3, r8: Test bit b3 in register r8, set zero flag if bit
/// not set
///
/// Cycles: 2
/// Bytes: 2
/// Flags:
///     Z=Set if bit b3 is 0
///     N=0
///     H=1
fn BIT_b3_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 10[b3][r8]: RES b3, r8: Set bit b3 in register r8 to 0. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2
/// Bytes: 2
fn RES_b3_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

/// 11[b3][r8]: SET b3, r8: Set bit b3 in register r8 to 1. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2
/// Bytes: 2
fn SET_b3_r8(self: CPU) void {
    _ = self;
    @panic("not implemented");
}

test "NOP" {
    // setup fake RAM
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.PC == 1);
}

test "LD_r16_imm16" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    RAM[0] = 0b00000001; // Opcode for LD BC, imm16
    RAM[1] = 0x34; // Low byte
    RAM[2] = 0x12; // High byte
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.B == 0x34); // Low byte
    try std.testing.expect(cpu.regs.C == 0x12); // High byte
    try std.testing.expect(cpu.regs.PC == 3);

    RAM[3] = 0b00110001; // Opcode for LD SP, imm16
    RAM[4] = 0x78; // Low byte
    RAM[5] = 0x56; // High byte
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.SP == 0x7856);
    try std.testing.expect(cpu.regs.PC == 6);
}

test "LD_r16mem_A" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0xAB; // A register
    RAM[0] = 0b00000010; // Opcode for LD (BC), A
    cpu.regs.B = 0x34; // B register (high byte of BC)
    cpu.regs.C = 0x12; // C register (low byte of BC)
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(RAM[0x3412] == 0xAB);
    try std.testing.expect(cpu.regs.PC == 1);

    RAM[1] = 0b00100010; // Opcode for LD (HLI), A
    cpu.regs.H = 0x56; // H register (high byte of HL)
    cpu.regs.L = 0xFF; // L register (low byte of HL)
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(RAM[0x56FF] == 0xAB);
    try std.testing.expect(cpu.regs.H == 0x57);
    try std.testing.expect(cpu.regs.L == 0x00);
    try std.testing.expect(cpu.regs.PC == 2);

    RAM[2] = 0b00110010; // Opcode for LD (HLD), A
    cpu.regs.H = 0x4A; // H register (high byte of HL)
    cpu.regs.L = 0xBC; // L register (low byte of HL)
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(RAM[0x4ABC] == 0xAB);
    try std.testing.expect(cpu.regs.H == 0x4A);
    try std.testing.expect(cpu.regs.L == 0xBB);
    try std.testing.expect(cpu.regs.PC == 3);
}

test "LD_A_r16mem" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    RAM[0x3412] = 0xCD;
    RAM[0] = 0b00001010; // Opcode for LD A, (BC)
    cpu.regs.B = 0x34; // B register (high byte of BC)
    cpu.regs.C = 0x12; // C register (low byte of BC)
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0xCD); // A register
    try std.testing.expect(cpu.regs.PC == 1);
}

test "LD_imm16_SP" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.SP = 0x9ABC;
    RAM[0] = 0b00001000; // Opcode for LD (imm16), SP
    RAM[1] = 0x10; // Low byte of imm16
    RAM[2] = 0x80; // High byte of imm16
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(RAM[0x1080] == 0xBC); // Low byte of SP
    try std.testing.expect(RAM[0x1081] == 0x9A); // High byte of SP
    try std.testing.expect(cpu.regs.PC == 3);
}

test "INC_r16" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.B = 0xFF; // B register
    cpu.regs.C = 0xFF; // C register
    RAM[0] = 0b00000011; // Opcode for INC BC
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.B == 0x00); // B register
    try std.testing.expect(cpu.regs.C == 0x00); // C register
    try std.testing.expect(cpu.regs.PC == 1);

    cpu.regs.SP = 0x1234; // SP
    RAM[1] = 0b00110011; // Opcode for INC SP
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.SP == 0x1235); // SP
    try std.testing.expect(cpu.regs.PC == 2);
}

test "DEC_r16" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.B = 0x00; // B register
    cpu.regs.C = 0x00; // C register
    RAM[0] = 0b00001011; // Opcode for DEC BC
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.B == 0xFF); // B register
    try std.testing.expect(cpu.regs.C == 0xFF); // C register
    try std.testing.expect(cpu.regs.PC == 1);

    cpu.regs.SP = 0x0000; // SP
    RAM[1] = 0b00111011; // Opcode for DEC SP
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.SP == 0xFFFF); // SP
    try std.testing.expect(cpu.regs.PC == 2);
}

test "ADD_HL_r16" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.H = 0x1F; // H register
    cpu.regs.L = 0x34; // L register
    cpu.regs.B = 0x01; // B register
    cpu.regs.C = 0x10; // C register
    RAM[0] = 0b00001001; // Opcode for ADD HL, BC
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.H == 0x20);
    try std.testing.expect(cpu.regs.L == 0x44);
    try std.testing.expect(cpu.regs.F == 0b00100000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);

    cpu.regs.F = 0b10100000;
    cpu.regs.H = 0xFF; // H register
    cpu.regs.L = 0xFF; // L register
    cpu.regs.D = 0x00; // D register
    cpu.regs.E = 0x01; // E register
    RAM[1] = 0b00011001; // Opcode for ADD HL, DE
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.H == 0x00);
    try std.testing.expect(cpu.regs.L == 0x00);
    try std.testing.expect(cpu.regs.F == 0b10110000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 2);
}

test "INC_r8" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0xFF; // A register
    RAM[0] = 0b00111100; // Opcode for INC A
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0x00); // A register
    try std.testing.expect(cpu.regs.F == 0b10100000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "DEC_r8" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0x00; // A register
    RAM[0] = 0b00111101; // Opcode for DEC A
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0xFF); // A register
    try std.testing.expect(cpu.regs.F == 0b01100000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "LD_r8_imm8" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    RAM[0] = 0b00000110; // Opcode for LD B, imm8
    RAM[1] = 0x7A; // imm8 value
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.B == 0x7A); // B register
    try std.testing.expect(cpu.regs.PC == 2);
}

test "RLCA" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0b10000001; // A register
    RAM[0] = 0b00000111; // Opcode for RLCA
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0b00000011); // A register
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "RRCA" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0b00000011; // A register
    RAM[0] = 0b00001111; // Opcode for RRCA
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0b10000001); // A register
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "RLA" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0b10000001; // A register
    cpu.regs.F = 0b00010000; // Set Carry flag
    RAM[0] = 0b00010111; // Opcode for RLA
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0b00000011); // A register
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "RRA" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0b00000011; // A register
    cpu.regs.F = 0b00010000; // Set Carry flag
    RAM[0] = 0b00011111; // Opcode for RRA
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0b10000001); // A register
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "DAA" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0x98; // A register
    cpu.regs.F = 0b01110000; // Clear all flags
    RAM[0] = 0b00100111; // Opcode for DAA
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0x98 - 0x66);
    try std.testing.expect(cpu.regs.F == 0b01010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);

    cpu.regs.A = 0x12; // A register
    cpu.regs.F = 0b00110000; // Set N flag
    RAM[1] = 0b00100111; // Opcode for DAA
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0x12 + 0x66);
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 2);
}

test "CPL" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.A = 0b10101010; // A register
    RAM[0] = 0b00101111; // Opcode for CPL
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.A == 0b01010101); // A register
    try std.testing.expect(cpu.regs.F == 0b01100000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "SCF" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.F = 0b00000000; // Clear all flags
    RAM[0] = 0b00110111; // Opcode for SCF
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);
}

test "CCF" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.F = 0b00010000; // Set Carry flag
    RAM[0] = 0b00111111; // Opcode for CCF
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.F == 0b00000000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 1);

    RAM[1] = 0b00111111; // Opcode for CCF
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.regs.PC == 2);
}

test "JR_imm8" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    RAM[0] = 0b00011000; // Opcode for JR imm8
    RAM[1] = 0x05; // imm8 value
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.PC == 0x07); // PC should be 0 + 2 + 5

    RAM[8] = @bitCast(@as(i8, -2)); // imm8 value to jump back
    RAM[7] = 0b00011000; // Opcode for JR imm8
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.PC == 0x07); // PC should be 7 + 2 - 2
}

test "JR_cond_imm8" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    RAM[0] = 0b00100000; // Opcode for JR NZ, imm8
    RAM[1] = 0x04; // imm8 value
    cpu.regs.F = 0b00000000; // Z flag not set
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.PC == 0x06); // PC should be 0 + 2 + 4

    RAM[6] = 0b00100000; // Opcode for JR NZ, imm8
    RAM[7] = 0x04; // imm8 value
    cpu.regs.F = 0b10000000; // Z flag set
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.PC == 0x08); // PC should be 6 + 2
}

test "LD_r8_r8" {
    var RAM: [0x8000]u8 = @splat(0);
    var cpu = CPU.init(&RAM);
    cpu.regs.B = 0x56; // B register
    RAM[0] = 0b01000000; // Opcode for LD B, B
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.B == 0x56); // B register
    try std.testing.expect(cpu.regs.PC == 1);

    cpu.regs.C = 0x78; // C register
    RAM[1] = 0b01000001; // Opcode for LD B, C
    cpu.execute();
    cpu.regs.PC += 1;
    try std.testing.expect(cpu.regs.B == 0x78); // B register
    try std.testing.expect(cpu.regs.PC == 2);
}

test "HALT" {
    // var RAM: [0x8000]u8 = @splat(0);
    // var cpu = CPU.init(&RAM);
    // RAM[0] = 0b01110110; // Opcode for HALT
    // cpu.execute();
    // cpu.regs.PC += 1;
    // try std.testing.expect(cpu.halted == true);
    // try std.testing.expect(cpu.registers.PC == 1);
}
