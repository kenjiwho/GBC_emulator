const std = @import("std");
const Cpu = @import("Cpu.zig");
const Registers = @import("Registers.zig");

// opcode function type
const DispatchFn = *const fn (cpu: *Cpu) Cpu.CpuError!void;

const dispatch_ptr_tbl: [4]DispatchFn = .{
    dispatch0,
    dispatch1,
    dispatch2,
    dispatch3,
};

/// execute the next instruction (fetch-decode-execute)
pub fn execute(cpu: *Cpu) Cpu.CpuError!void {
    try dispatch_ptr_tbl[(cpu.opcode >> 6)](cpu);
}

// --------------------------------- opcode dispatchers --------------------
fn dispatch0(cpu: *Cpu) Cpu.CpuError!void {
    switch (cpu.opcode) { // full opcode
        0x00 => NOP(cpu),
        0x08 => LD_imm16_SP(cpu),
        0x18 => JR_imm8(cpu),
        0x10 => STOP(cpu),
        0x07 => RLCA(cpu),
        0x0F => RRCA(cpu),
        0x17 => RLA(cpu),
        0x1F => RRA(cpu),
        0x27 => DAA(cpu),
        0x2F => CPL(cpu),
        0x37 => SCF(cpu),
        0x3F => CCF(cpu),
        0x20, 0x28, 0x30, 0x38 => JR_cond_imm8(cpu),
        else => {
            switch (cpu.opcode & 0xF) { // lower 4 bits
                0x1 => LD_r16_imm16(cpu),
                0x2 => LD_r16mem_A(cpu),
                0x3 => INC_r16(cpu),
                0x4, 0xC => INC_r8(cpu),
                0x5, 0xD => DEC_r8(cpu),
                0x6, 0xE => LD_r8_imm8(cpu),
                0x9 => ADD_HL_r16(cpu),
                0xA => LD_A_r16mem(cpu),
                0xB => DEC_r16(cpu),
                else => unreachable,
            }
        },
    }
}
fn dispatch1(cpu: *Cpu) Cpu.CpuError!void {
    switch (cpu.opcode) { // full opcode
        0x76 => HALT(cpu),
        else => LD_r8_r8(cpu),
    }
}
fn dispatch2(cpu: *Cpu) Cpu.CpuError!void {
    switch (cpu.opcode >> 3) { // upper 5 bits
        0b10000 => ADD_A_r8(cpu),
        0b10001 => ADC_A_r8(cpu),
        0b10010 => SUB_A_r8(cpu),
        0b10011 => SBC_A_r8(cpu),
        0b10100 => AND_A_r8(cpu),
        0b10101 => XOR_A_r8(cpu),
        0b10110 => OR_A_r8(cpu),
        0b10111 => CP_A_r8(cpu),
        else => unreachable,
    }
}
fn dispatch3(cpu: *Cpu) Cpu.CpuError!void {
    switch (cpu.opcode) { // full opcode
        0xC6 => ADD_A_imm8(cpu),
        0xCE => ADC_A_imm8(cpu),
        0xD6 => SUB_A_imm8(cpu),
        0xDE => SBC_A_imm8(cpu),
        0xE6 => AND_A_imm8(cpu),
        0xEE => XOR_A_imm8(cpu),
        0xF6 => OR_A_imm8(cpu),
        0xFE => CP_A_imm8(cpu),
        0xC9 => RET(cpu),
        0xD9 => RETI(cpu),
        0xC3 => JP_imm16(cpu),
        0xE9 => JP_HL(cpu),
        0xCD => CALL_imm16(cpu),
        0xCB => CB_prefix(cpu),
        0xE2 => LDH_C_A(cpu),
        0xE0 => LDH_imm8_A(cpu),
        0xEA => LD_imm16_A(cpu),
        0xF2 => LDH_A_C(cpu),
        0xF0 => LDH_A_imm8(cpu),
        0xFA => LD_A_imm16(cpu),
        0xE8 => ADD_SP_imm8(cpu),
        0xF8 => LD_HL_SPimm8(cpu),
        0xF9 => LD_SP_HL(cpu),
        0xF3 => DI(cpu),
        0xFB => EI(cpu),
        // invalid opcodes
        0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD => return Cpu.CpuError.InvalidOpcode,
        else => {
            switch (cpu.opcode & 0b111) { // lower 3 bits
                0b000 => RET_cond(cpu),
                0b001 => POP_r16stk(cpu),
                0b010 => JP_cond_imm16(cpu),
                0b100 => CALL_cond_imm16(cpu),
                0b101 => PUSH_r16stk(cpu),
                0b111 => RST_tgt3(cpu),
                else => unreachable,
            }
        },
    }
}

// --------------------------------- CPU Instructions -------------------------
// --------------------------------- block 0 ----------------------------------
/// 00000000: NOP: No Operation
///
/// Cycles: 1
/// Bytes: 1
fn NOP(cpu: *const Cpu) void {
    _ = cpu;
}

/// 00[r16]0001[imm16]: LD r16, imm16: Copy the value imm16 into register r16
///
/// Cycles: 3
/// Bytes: 3
fn LD_r16_imm16(cpu: *Cpu) void {
    const r16: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const imm16 = cpu.getImm16();

    cpu.setR16(r16, imm16);
}

/// 00[r16mem]0010: LD [r16mem], A: Store value of register A into memory pointed to by r16mem
/// (if hli/hld, increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_r16mem_A(cpu: *Cpu) void {
    const r16mem: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const addr = cpu.getR16mem(r16mem);

    cpu.bus.write(addr, cpu.regs.A);
}

/// 00[r16mem]1010: LD A, [r16mem]: Load value of memory pointed to by r16mem into register A
/// (hli or hld increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_A_r16mem(cpu: *Cpu) void {
    const r16mem: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const addr = cpu.getR16mem(r16mem);

    cpu.regs.A = cpu.bus.read(addr);
}

/// 00001000[imm16]: LD [imm16], SP: Copy SP & $FF (lower byte of SP) at address imm16 and
/// SP >> 8 (upper byte of SP) at address imm16 + 1.
///
/// Cycles: 5
/// Bytes: 3
fn LD_imm16_SP(cpu: *Cpu) void {
    const imm16 = cpu.getImm16();
    cpu.bus.write(imm16, @intCast(cpu.regs.SP & 0xFF));
    cpu.bus.write(imm16 + 1, @intCast(cpu.regs.SP >> 8));
}

/// 00[r16]0011: INC r16: Increment the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn INC_r16(cpu: *Cpu) void {
    cpu.internalCycle(); // 16-bit arithmetic takes consumes an M-cycle
    const r16: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const new_val = cpu.getR16(r16) +% 1;

    cpu.setR16(r16, new_val);
}

/// 00[r16]1011: DEC r16: Decrement the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn DEC_r16(cpu: *Cpu) void {
    cpu.internalCycle();
    const r16: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const new_val = cpu.getR16(r16) -% 1;

    cpu.setR16(r16, new_val);
}

/// 00[r16]1001: ADD HL, r16: Add the value in r16 to HL
///
/// Cycles: 2
/// Bytes: 1
/// Flags:
///     N=0
///     H=Set if overflow from bit 11
///     C=Set if overflow from bit 15
fn ADD_HL_r16(cpu: *Cpu) void {
    cpu.internalCycle();
    const r16: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const val = cpu.getR16(r16);

    const hl = cpu.regs.getHL();
    const new_hl, const c = @addWithOverflow(hl, val); // add with carry flag

    cpu.regs.setHL(new_hl); // set HL register
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, ((@as(u32, hl) & 0x0FFF) + (@as(u32, val) & 0x0FFF)) > 0x0FFF);
    cpu.setFlag(.C, c == 1);
}

/// 00[r8]100: INC r8: Increment the value in register r8 by 1
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
fn INC_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast((cpu.opcode >> 3) & 0b111);
    const val = cpu.getR8(r8);
    const new_val = val +% 1;

    cpu.setR8(r8, new_val);
    cpu.setFlag(.Z, new_val == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, ((val & 0x0F) + (1 & 0x0F)) > 0x0F);
}

/// 00[r8]101: DEC r8: Decrement the value in register r8 by 1
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
fn DEC_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast((cpu.opcode >> 3) & 0b111);
    const val = cpu.getR8(r8);
    const new_val = val -% 1;

    cpu.setR8(r8, new_val);
    cpu.setFlag(.Z, new_val == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, (val & 0x0F) < (1 & 0x0F));
}

/// 00[r8]110[imm8]: LD r8, imm8: Copy the value imm8 into register r8
///
/// Cycles: 2
/// Bytes: 2
fn LD_r8_imm8(cpu: *Cpu) void {
    const r8: u3 = @intCast((cpu.opcode >> 3) & 0b111);
    const imm8 = cpu.getImm8(u8);

    cpu.setR8(r8, imm8);
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
fn RLCA(cpu: *Cpu) void {
    const carry = cpu.regs.A >> 7;

    cpu.regs.A = std.math.rotl(u8, cpu.regs.A, 1);
    cpu.setFlag(.Z, false);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn RRCA(cpu: *Cpu) void {
    const carry = cpu.regs.A & 0b1;

    cpu.regs.A = std.math.rotr(u8, cpu.regs.A, 1);
    cpu.setFlag(.Z, false);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn RLA(cpu: *Cpu) void {
    const old_carry = @intFromBool(cpu.getFlag(.C));
    const new_carry = (cpu.regs.A >> 7) & 0b1;

    cpu.regs.A = (cpu.regs.A << 1) | old_carry;
    cpu.setFlag(.Z, false);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, new_carry == 1);
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
fn RRA(cpu: *Cpu) void {
    const old_carry: u8 = @intFromBool(cpu.getFlag(.C));
    const new_carry = cpu.regs.A & 0b1;

    cpu.regs.A = (cpu.regs.A >> 1) | (old_carry << 7);
    cpu.setFlag(.Z, false);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, new_carry == 1);
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
fn DAA(cpu: *Cpu) void {
    var adjustment: u8 = 0;
    if (cpu.getFlag(.N)) {
        if (cpu.getFlag(.H)) {
            adjustment += 0x6;
        }
        if (cpu.getFlag(.C)) {
            adjustment += 0x60;
        }
        cpu.regs.A -%= adjustment;
    } else {
        if (cpu.getFlag(.H) or (cpu.regs.A & 0xF) > 0x9) {
            adjustment += 0x6;
        }
        if (cpu.getFlag(.C) or (cpu.regs.A) > 0x99) {
            adjustment += 0x60;
            cpu.setFlag(.C, true);
        }
        cpu.regs.A +%= adjustment;
    }

    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.H, false);
}

/// 00101111: CPL: ComPLement accumulator (A = ~A) (bitwise NOT)
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=1
///     H=1
fn CPL(cpu: *Cpu) void {
    cpu.regs.A = ~cpu.regs.A;

    cpu.setFlag(.N, true);
    cpu.setFlag(.H, true);
}

/// 00110111: SCF: Set Carry Flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=0
///     H=0
///     C=1
fn SCF(cpu: *Cpu) void {
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, true);
}

/// 00111111: CCF: Complement Carry Flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=0
///     H=0
///     C=Inverted
fn CCF(cpu: *Cpu) void {
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, !cpu.getFlag(.C));
}

/// 00011000[imm8]: jr imm8: Relative Jump to address imm8 (PC + 1 + imm8)
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3
/// Bytes: 2
fn JR_imm8(cpu: *Cpu) void {
    const offset = cpu.getImm8(i8);

    cpu.internalCycle();

    // cast pc and offset to i32 to perform signed addition
    const pc_i32: i32 = @intCast(cpu.regs.PC);
    const offset_i32: i32 = @intCast(offset);
    const result: u32 = @bitCast(pc_i32 + offset_i32);
    cpu.regs.PC = @truncate(result);
}

/// 001[cond]000[imm8]: JR cond, imm8: Relative Jump to address imm8
/// (SP + imm8) if condition cond is met.
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3 taken / 2 untaken
/// Bytes: 2
fn JR_cond_imm8(cpu: *Cpu) void {
    const cond: u2 = @intCast((cpu.opcode >> 3) & 0b11);
    if (cpu.checkCondition(cond)) {
        JR_imm8(cpu);
    } else {
        _ = cpu.getImm8(u8); // skip imm8
    }
}

/// 00010000: STOP: What happens depends on the state of the emulator. Refer to
/// this picture for details: https://gbdev.io/pandocs/imgs/stop_diagram.svg
///
/// Cycles: -
/// Bytes: 2 (depends on emulator state)
fn STOP(cpu: *Cpu) void {
    const joyp = cpu.bus.io.getJoyp();
    const key1 = cpu.bus.io.getKey1();
    const IE = cpu.bus.IE;
    const IF = cpu.bus.io.getIF();
    const pending_interrupts = IE & IF;

    if ((joyp & 0x0F) != 0x0F) { // button pressed
        if (pending_interrupts != 0) {
            // 1-byte opcode no STOP
            return;
        }
        // 2-byte opcode HALT
        _ = cpu.getImm8(u8);
        cpu.halted = true;
        return;
    }

    if ((key1 & 0b1) == 0) { // speed switch not requested
        if (pending_interrupts != 0) {
            // 1-byte opcode STOP
            cpu.bus.timer.write(0xFF04, 0x00); // reset DIV
            cpu.stopped = true;
            return;
        }
        // 2-byte opcode STOP
        _ = cpu.getImm8(u8);
        cpu.bus.timer.write(0xFF04, 0x00); // reset DIV
        cpu.stopped = true;
        return;
    }

    if (pending_interrupts != 0) {
        if (cpu.IME) {
            cpu.bus.timer.write(0xFF04, 0x00); // reset DIV
            cpu.bus.io.toggleSpeed(); // set double speed
            return;
        }
        @panic("STOP bug: non-deterministic behavior");
    }

    _ = cpu.getImm8(u8);
    cpu.bus.timer.write(0xFF04, 0x00); // reset DIV
    cpu.halted = true;
    cpu.halted_timer = 0x20000; // halted should last 0x20000 T-cycles
    cpu.bus.io.toggleSpeed();
}

// ------------------------------- end block 0 --------------------------------
// ---------------- block 1: 8-bit register-to-register loads -----------------

/// 01[dest(r8)][src(r8)]: LD r8, r8: Copy value from src(r8) to dest(r8)
/// Storing a register into itcpu is a no-op. trying to encode LD [hl], [hl]
/// yields the halt instruction
///
/// Cycles: 1 or 2 if (HL)
/// Bytes: 1
fn LD_r8_r8(cpu: *Cpu) void {
    const src: u3 = @intCast(cpu.opcode & 0b111);
    const dest: u3 = @intCast((cpu.opcode >> 3) & 0b111);

    const value = cpu.getR8(src);

    cpu.setR8(dest, value);
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
fn HALT(cpu: *Cpu) void {
    if (cpu.IME) {
        cpu.halted = true;
    } else {
        const IE = cpu.bus.IE;
        const IF = cpu.bus.io.getIF();
        if ((IE & IF) == 0) {
            cpu.halted = true;
        } else {
            cpu.HALT_bug = true;
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
fn ADD_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);
    const old_a = cpu.regs.A;

    cpu.regs.A, const c = @addWithOverflow(old_a, value);
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, ((old_a & 0x0F) + (value & 0x0F)) > 0x0F);
    cpu.setFlag(.C, c == 1);
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
fn ADC_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);
    const carry = @intFromBool(cpu.getFlag(.C));
    const old_a = cpu.regs.A;

    const sum = @as(u9, old_a) + value + carry;

    cpu.regs.A = @truncate(sum); // wrap back to u8
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, ((old_a & 0x0F) + (value & 0x0F) + carry) > 0x0F);
    cpu.setFlag(.C, sum > 0xFF);
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
fn SUB_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);
    const old_a = cpu.regs.A;

    cpu.regs.A, const c = @subWithOverflow(old_a, value);
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, (old_a & 0x0F) < (value & 0x0F));
    cpu.setFlag(.C, c == 1);
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
fn SBC_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);
    const carry = @intFromBool(cpu.getFlag(.C));
    const old_a = cpu.regs.A;

    const sum = @as(i16, old_a) - value - carry;
    const half_check = (@as(i16, old_a) & 0xF) - (value & 0xF) - carry;

    cpu.regs.A = @truncate(@as(u16, @bitCast(sum))); // wrap back to u8
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, half_check < 0);
    cpu.setFlag(.C, sum < 0);
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
fn AND_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);

    cpu.regs.A = cpu.regs.A & value;
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, true);
    cpu.setFlag(.C, false);
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
fn XOR_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);

    cpu.regs.A = cpu.regs.A ^ value;
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, false);
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
fn OR_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);

    cpu.regs.A = cpu.regs.A | value;
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, false);
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
fn CP_A_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const value = cpu.getR8(r8);
    const old_a = cpu.regs.A;

    const res, const c = @subWithOverflow(old_a, value);
    cpu.setFlag(.Z, res == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, (old_a & 0x0F) < (value & 0x0F));
    cpu.setFlag(.C, c == 1);
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
fn ADD_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const old_a = cpu.regs.A;

    cpu.regs.A, const c = @addWithOverflow(old_a, imm8);
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, ((old_a & 0x0F) + (imm8 & 0x0F)) > 0x0F);
    cpu.setFlag(.C, c == 1);
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
fn ADC_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const carry = @intFromBool(cpu.getFlag(.C));
    const old_a = cpu.regs.A;

    const sum = @as(u9, old_a) + imm8 + carry;

    cpu.regs.A = @truncate(sum); // wrap back to u8
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, ((old_a & 0x0F) + (imm8 & 0x0F) + carry) > 0x0F);
    cpu.setFlag(.C, sum > 0xFF);
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
fn SUB_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const old_a = cpu.regs.A;

    cpu.regs.A, const c = @subWithOverflow(old_a, imm8);
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, (old_a & 0x0F) < (imm8 & 0x0F));
    cpu.setFlag(.C, c == 1);
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
fn SBC_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const carry = @intFromBool(cpu.getFlag(.C));
    const old_a = cpu.regs.A;

    const sum = @as(i16, old_a) - imm8 - carry;
    const half_check = (@as(i16, old_a) & 0xF) - (imm8 & 0xF) - carry;

    cpu.regs.A = @truncate(@as(u16, @bitCast(sum))); // wrap back to u8
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, half_check < 0);
    cpu.setFlag(.C, sum < 0);
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
fn AND_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);

    cpu.regs.A = cpu.regs.A & imm8;
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, true);
    cpu.setFlag(.C, false);
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
fn XOR_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);

    cpu.regs.A = cpu.regs.A ^ imm8;
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, false);
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
fn OR_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    cpu.regs.A = cpu.regs.A | imm8;
    cpu.setFlag(.Z, cpu.regs.A == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, false);
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
fn CP_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const old_a = cpu.regs.A;

    const res, const c = @subWithOverflow(old_a, imm8);
    cpu.setFlag(.Z, res == 0);
    cpu.setFlag(.N, true);
    cpu.setFlag(.H, (old_a & 0x0F) < (imm8 & 0x0F));
    cpu.setFlag(.C, c == 1);
}

/// 11001001: RET: Return from subroutine. This is basically a POP PC.
///
/// Cycles: 4
/// Bytes: 1
fn RET(cpu: *Cpu) void {
    const target = cpu.pop();
    cpu.internalCycle();
    cpu.regs.PC = target;
}

/// 110[cond]000: RET cond: Return from subroutine if condition cond is met.
///
/// Cycles: 5 taken / 2 untaken
/// Bytes: 1
fn RET_cond(cpu: *Cpu) void {
    const cond: u2 = @intCast((cpu.opcode >> 3) & 0b11);

    cpu.internalCycle(); // decision cycle
    if (cpu.checkCondition(cond)) {
        RET(cpu);
    }
}

/// 11011001: RETI: Return from interrupt and enable interrupts. This is
/// basically a POP PC followed by setting the IME flag to 1
/// (EI followed by RET).
///
/// Cycles: 4
/// Bytes: 1
fn RETI(cpu: *Cpu) void {
    RET(cpu);
    cpu.IME = true;
}

/// 11000011[imm16]: JP imm16: Jump to address imm16 (copy n16 into PC).
///
/// Cycles: 4
/// Bytes: 3
fn JP_imm16(cpu: *Cpu) void {
    const target = cpu.getImm16();

    cpu.internalCycle();
    cpu.regs.PC = target;
}

/// 110[cond]010[imm16]: JP cond, imm16: Jump to address imm16 if condition
/// cond is met.
///
/// Cycles: 4 taken / 3 untaken
/// Bytes: 3
fn JP_cond_imm16(cpu: *Cpu) void {
    const cond: u2 = @intCast((cpu.opcode >> 3) & 0b11);

    if (cpu.checkCondition(cond)) {
        JP_imm16(cpu);
    } else {
        _ = cpu.getImm16(); // skip imm16
    }
}

/// 11101001: JP HL: Jump to address in HL (copy HL into PC).
///
/// Cycles: 1
/// Bytes: 1
fn JP_HL(cpu: *Cpu) void {
    cpu.regs.PC = cpu.regs.getHL();
}

/// 11001101[imm16]: CALL imm16: Call address imm16. This pushes the address
/// of the instruction after the CALL on the stack, such that RET can pop it
/// later; then, it executes an implicit JP imm16
///
/// Cycles: 6
/// Bytes: 3
fn CALL_imm16(cpu: *Cpu) void {
    const target = cpu.getImm16();

    cpu.push(cpu.regs.PC);

    cpu.regs.PC = target;
}

/// 110[cond]100: CALL cond, imm16: Call address imm16 if condition cond is met
///
/// Cycles: 6 taken / 3 untaken
/// Bytes: 3
fn CALL_cond_imm16(cpu: *Cpu) void {
    const cond: u2 = @intCast((cpu.opcode >> 3) & 0b11);

    if (cpu.checkCondition(cond)) {
        CALL_imm16(cpu);
    } else {
        _ = cpu.getImm16(); // skip imm16
    }
}

/// 11[tgt3]111: RST tgt3: Call to address tgt3*8
///
/// Cycles: 4
/// Bytes: 1
fn RST_tgt3(cpu: *Cpu) void {
    const tgt3 = (cpu.opcode >> 3) & 0b111;

    cpu.push(cpu.regs.PC);
    cpu.regs.PC = tgt3 * 8;
}

/// 11[r16stk]0001: POP r16stk: Pop register r16stk off the stack
///
/// Cycles: 3
/// Bytes: 1
fn POP_r16stk(cpu: *Cpu) void {
    const value = cpu.pop();
    const r16stk: u2 = @intCast((cpu.opcode >> 4) & 0b11);

    cpu.setR16stk(r16stk, value);
}

/// 11[r16stk]0101: PUSH r16stk: Push register r16stk onto the stack
///
/// Cycles: 4
/// Bytes: 1
fn PUSH_r16stk(cpu: *Cpu) void {
    const r16stk: u2 = @intCast((cpu.opcode >> 4) & 0b11);
    const value = cpu.getR16stk(r16stk);

    cpu.push(value);
}

/// 11100010: LDH [c], A: Store value of register A into byte at address
/// $FF00 + C
///
/// Cycles: 2
/// Bytes: 1
fn LDH_C_A(cpu: *Cpu) void {
    const address = 0xFF00 + @as(u16, cpu.regs.C);

    cpu.bus.write(address, cpu.regs.A);
}

/// TRUTH UNKNOWN
/// 11100000[imm8]: LDH [imm8], A: Store value of register A into byte at
/// address $FF00 + imm8
///
/// Cycles: 3
/// Bytes: 2
fn LDH_imm8_A(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const address = 0xFF00 + @as(u16, imm8);

    cpu.bus.write(address, cpu.regs.A);
}

/// 11101010[imm16]: LD [imm16], A: Copy the value of register A into the byte
/// at address imm16
///
/// Cycles: 4
/// Bytes: 3
fn LD_imm16_A(cpu: *Cpu) void {
    const address = cpu.getImm16();

    cpu.bus.write(address, cpu.regs.A);
}

/// 11110010: LDH A, [c]: Copy the byte at address $FF00 + C into register A
///
/// Cycles: 2
/// Bytes: 1
fn LDH_A_C(cpu: *Cpu) void {
    const address = 0xFF00 + @as(u16, cpu.regs.C);

    cpu.regs.A = cpu.bus.read(address);
}

/// TRUTH UNKNOWN
/// 11110000[imm8]: LDH A, [imm8]: Copy the byte at address $FF00 + imm8
/// into register A
///
/// Cycles: 3
/// Bytes: 2
fn LDH_A_imm8(cpu: *Cpu) void {
    const imm8 = cpu.getImm8(u8);
    const address = 0xFF00 + @as(u16, imm8);

    cpu.regs.A = cpu.bus.read(address);
}

/// 11111010[imm16]: LD A, [imm16]: Load value at address imm16 into register A
///
/// Cycles: 4
/// Bytes: 3
fn LD_A_imm16(cpu: *Cpu) void {
    const address = cpu.getImm16();

    cpu.regs.A = cpu.bus.read(address);
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
fn ADD_SP_imm8(cpu: *Cpu) void {
    const offset = cpu.getImm8(i8);
    const old_sp = cpu.regs.SP;
    const offset_bits: u8 = @bitCast(offset);

    cpu.internalCycle();
    cpu.internalCycle();
    // cast sp and offset to i32 to perform signed addition
    const sp_i32: i32 = @intCast(old_sp);
    const offset_i32: i32 = @intCast(offset);
    const result: u32 = @bitCast(sp_i32 +% offset_i32);
    cpu.regs.SP = @truncate(result);

    const h_check = (old_sp & 0xF) + (offset_bits & 0xF);
    const c_check = (old_sp & 0xFF) + offset_bits;
    cpu.setFlag(.Z, false);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, h_check > 0xF);
    cpu.setFlag(.C, c_check > 0xFF);
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
fn LD_HL_SPimm8(cpu: *Cpu) void {
    const offset = cpu.getImm8(i8);
    const old_sp = cpu.regs.SP;
    const offset_bits: u8 = @bitCast(offset);

    cpu.internalCycle();
    // cast sp and offset to i32 to perform signed addition
    const sp_i32: i32 = @intCast(old_sp);
    const offset_i32: i32 = @intCast(offset);
    const result: u32 = @bitCast(sp_i32 +% offset_i32);
    cpu.regs.setHL(@truncate(result));

    const h_check = (old_sp & 0xF) + (offset_bits & 0xF);
    const c_check = (old_sp & 0xFF) + offset_bits;
    cpu.setFlag(.Z, false);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, h_check > 0xF);
    cpu.setFlag(.C, c_check > 0xFF);
}

/// 11111001: LD A, HL: Copy register HL into stack pointer SP
///
/// Cycles: 2
/// Bytes: 1
fn LD_SP_HL(cpu: *Cpu) void {
    cpu.internalCycle();
    cpu.regs.SP = cpu.regs.getHL();
}

/// 11111011: EI: Enable Interrupts (IME = 1)
/// The flag is only set after the instruction following EI
///
/// Cycles: 1
/// Bytes: 1
fn EI(cpu: *Cpu) void {
    cpu.IME_scheduled = true;
}

/// 11110011: DI: Disable Interrupts (IME = 0)
///
/// Cycles: 1
/// Bytes: 1
fn DI(cpu: *Cpu) void {
    cpu.IME = false;
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
fn CB_prefix(cpu: *Cpu) void {
    cpu.opcode = cpu.fetch();

    switch (cpu.opcode >> 6) {
        1 => BIT_b3_r8(cpu),
        2 => RES_b3_r8(cpu),
        3 => SET_b3_r8(cpu),
        else => {
            switch (cpu.opcode >> 3) {
                0 => RLC_r8(cpu),
                1 => RRC_r8(cpu),
                2 => RL_r8(cpu),
                3 => RR_r8(cpu),
                4 => SLA_r8(cpu),
                5 => SRA_r8(cpu),
                6 => SWAP_r8(cpu),
                7 => SRL_r8(cpu),
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
fn RLC_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const carry = value >> 7;

    value = std.math.rotl(u8, value, 1);

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn RRC_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const carry = value & 0b1;

    value = std.math.rotr(u8, value, 1);

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn RL_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const old_carry = @intFromBool(cpu.getFlag(.C));
    const new_carry = (value >> 7) & 0b1;

    value = (value << 1) | old_carry;

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, new_carry == 1);
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
fn RR_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const old_carry: u8 = @intFromBool(cpu.getFlag(.C));
    const new_carry = value & 0b1;

    value = (value >> 1) | (old_carry << 7);

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, new_carry == 1);
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
fn SLA_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const carry = value >> 7;

    value <<= 1;

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn SRA_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const carry = value & 0b1;
    const bit7 = value & 0b10000000;

    value >>= 1;
    value |= bit7;

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn SWAP_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const high = value >> 4;
    const low = value & 0xF;

    value = (low << 4) | high;

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, false);
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
fn SRL_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    var value = cpu.getR8(r8);
    const carry = value & 0b1;

    value >>= 1;

    cpu.setR8(r8, value);
    cpu.setFlag(.Z, value == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, false);
    cpu.setFlag(.C, carry == 1);
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
fn BIT_b3_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const b3: u3 = @intCast((cpu.opcode >> 3) & 0b111);
    const value = cpu.getR8(r8);

    const bit = (value >> b3) & 0b1;

    cpu.setFlag(.Z, bit == 0);
    cpu.setFlag(.N, false);
    cpu.setFlag(.H, true);
}

/// 10[b3][r8]: RES b3, r8: Set bit b3 in register r8 to 0. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
fn RES_b3_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const b3: u3 = @intCast((cpu.opcode >> 3) & 0b111);
    var value = cpu.getR8(r8);

    value &= (@as(u8, 1) << b3) ^ 0xFF;

    cpu.setR8(r8, value);
}

/// 11[b3][r8]: SET b3, r8: Set bit b3 in register r8 to 1. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2 or 4 if (HL)
/// Bytes: 2
fn SET_b3_r8(cpu: *Cpu) void {
    const r8: u3 = @intCast(cpu.opcode & 0b111);
    const b3: u3 = @intCast((cpu.opcode >> 3) & 0b111);
    var value = cpu.getR8(r8);

    value |= @as(u8, 1) << b3;

    cpu.setR8(r8, value);
}

const Bus = @import("Bus.zig");
const Timer = @import("Timer.zig");
test "NOP" {
    // setup fake RAM
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    try cpu.step();
    try std.testing.expectEqual(1, cpu.regs.PC);
    try std.testing.expectEqual(4, timer.counter);
}

test "LD_r16_imm16" {
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
    var timer = Timer.init(&bus);
    bus.timer = &timer;
    bus.write(0, 0xD3); // Invalid Opcode
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(1, 0xDB);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(2, 0xDD);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(3, 0xE3);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(4, 0xE4);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(5, 0xEB);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(6, 0xEC);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(7, 0xED);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(8, 0xF4);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(9, 0xFC);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
    bus.write(10, 0xFD);
    try std.testing.expectError(Cpu.CpuError.InvalidOpcode, cpu.step());
}

// ------------------------ CB prefix tests ----------------------
test "RLC_r8" {
    var bus = Bus.init();
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
    var cpu = Cpu.init(&bus);
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
