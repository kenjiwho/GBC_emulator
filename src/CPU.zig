const CPU = @This();

const std = @import("std");
const Registers = @import("Registers.zig");
const Context = @import("Context.zig");

// opcode function type
const DispatchFn = *const fn (ctx: Context) void;

registers: Registers = Registers.init(), // 8x8-bit registers or 4x16-bit registers (AF, BC, DE, HL) + stack pointer + program counter
comptime dispatch_ptr_tbl: [4]DispatchFn = .{
    dispatch0,
    dispatch1,
    dispatch2,
    dispatch3,
},

pub fn init() CPU {
    return CPU{};
}

pub fn execute(self: *CPU, ctx: Context) void {
    self.dispatch_ptr_tbl[(ctx.opcode() >> 6)](ctx);
}

// --------------------------------- opcode dispatchers --------------------
fn dispatch0(ctx: Context) void {
    switch (ctx.opcode()) { // full opcode
        0x00 => NOP(ctx),
        0x08 => LD_imm16_SP(ctx),
        0x18 => JR_imm8(ctx),
        0x10 => STOP(ctx),
        0x07 => RLCA(ctx),
        0x0F => RRCA(ctx),
        0x17 => RLA(ctx),
        0x1F => RRA(ctx),
        0x27 => DAA(ctx),
        0x2F => CPL(ctx),
        0x37 => SCF(ctx),
        0x3F => CCF(ctx),
        0x20, 0x28, 0x30, 0x38 => JR_cond_imm8(ctx),
        else => {
            switch (ctx.opcode() & 0xF) { // lower 4 bits
                0x1 => LD_r16_imm16(ctx),
                0x2 => LD_r16mem_A(ctx),
                0x3 => INC_r16(ctx),
                0x4, 0xC => INC_r8(ctx),
                0x5, 0xD => DEC_r8(ctx),
                0x6, 0xE => LD_r8_imm8(ctx),
                0x9 => ADD_HL_r16(ctx),
                0xA => LD_A_r16mem(ctx),
                0xB => DEC_r16(ctx),
                else => unreachable,
            }
        },
    }
}
fn dispatch1(ctx: Context) void {
    _ = ctx;
}
fn dispatch2(ctx: Context) void {
    _ = ctx;
}
fn dispatch3(ctx: Context) void {
    _ = ctx;
}

// --------------------------------- CPU Instructions -------------------------
// --------------------------------- block 0 ----------------------------------
/// 00000000: NOP: No Operation
///
/// Cycles: 1
/// Bytes: 1
fn NOP(ctx: Context) void {
    _ = ctx;
}

/// 00[r16]0001[imm16]: LD r16, imm16: Copy the value imm16 into register r16
///
/// Cycles: 3
/// Bytes: 3
fn LD_r16_imm16(ctx: Context) void {
    const r16 = (ctx.opcode() >> 4) & 0b11;
    const imm16 = ctx.getImm16();

    ctx.regs.setR16(r16, imm16);
    ctx.pc.* += 2;
}

/// 00[r16mem]0010: LD [r16mem], A: Store value of register A into memory pointed to by r16mem
/// (if hli/hld, increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_r16mem_A(ctx: Context) void {
    const r16mem = (ctx.opcode() >> 4) & 0b11;
    const addr = ctx.regs.getR16mem(r16mem);

    ctx.RAM[addr] = ctx.regs.A;
}

/// 00[r16mem]1010: LD A, [r16mem]: Load value of memory pointed to by r16mem into register A
/// (hli or hld increment/decrement hl afterwards)
///
/// Cycles: 2
/// Bytes: 1
fn LD_A_r16mem(ctx: Context) void {
    const r16mem = (ctx.opcode() >> 4) & 0b11;
    const addr = ctx.regs.getR16mem(r16mem);

    ctx.regs.A = ctx.RAM[addr];
}

/// 00001000[imm16]: LD [imm16], SP: Copy SP & $FF (lower byte of SP) at address imm16 and
/// SP >> 8 (upper byte of SP) at address imm16 + 1.
///
/// Cycles: 5
/// Bytes: 3
fn LD_imm16_SP(ctx: Context) void {
    const imm16 = ctx.getImm16();
    ctx.RAM[imm16] = @intCast(ctx.sp.* & 0xFF);
    ctx.RAM[imm16 + 1] = @intCast(ctx.sp.* >> 8);
    ctx.pc.* += 2;
}

/// 00[r16]0011: INC r16: Increment the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn INC_r16(ctx: Context) void {
    const r16 = (ctx.opcode() >> 4) & 0b11;
    const new_val = ctx.regs.getR16(r16) +% 1;

    ctx.regs.setR16(r16, new_val);
}

/// 00[r16]1011: DEC r16: Decrement the value in register r16 by 1
///
/// Cycles: 2
/// Bytes: 1
fn DEC_r16(ctx: Context) void {
    const r16 = (ctx.opcode() >> 4) & 0b11;
    const new_val = ctx.regs.getR16(r16) -% 1;

    ctx.regs.setR16(r16, new_val);
}

/// 00[r16]1001: ADD HL, r16: Add the value in r16 to HL
///
/// Cycles: 2
/// Bytes: 1
/// Flags:
///     N=0
///     H=Set if overflow from bit 11
///     C=Set if overflow from bit 15
fn ADD_HL_r16(ctx: Context) void {
    const r16 = (ctx.opcode() >> 4) & 0b11;
    const val = ctx.regs.getR16(r16);

    const hl = ctx.regs.getR16(2);
    const new_hl, const c: u8 = @addWithOverflow(hl, val); // add with carry flag

    ctx.regs.setR16(2, new_hl); // set HL register
    ctx.regs.setFlag(.N, false);
    ctx.regs.setFlag(.H, ((@as(u32, hl) & 0x0FFF) + (@as(u32, val) & 0x0FFF)) > 0x0FFF);
    ctx.regs.setFlag(.C, c == 1);
}

/// 00[r8]100: INC r8: Increment the value in register r8 by 1
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=0
///     H=Set if overflow from bit 3
fn INC_r8(ctx: Context) void {
    const r8 = (ctx.opcode() >> 3) & 0b111;
    const val = ctx.regs.getR8(r8);
    const new_val = val +% 1;

    ctx.regs.setR8(r8, new_val);
    ctx.regs.setFlag(.Z, new_val == 0);
    ctx.regs.setFlag(.N, false);
    ctx.regs.setFlag(.H, ((val & 0x0F) + (1 & 0x0F)) > 0x0F);
}

/// 00[r8]101: DEC r8: Decrement the value in register r8 by 1
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     Z=Set if result is zero
///     N=1
///     H=Set if borrow from bit 4
fn DEC_r8(ctx: Context) void {
    const r8 = (ctx.opcode() >> 3) & 0b111;
    const val = ctx.regs.getR8(r8);
    const new_val = val -% 1;

    ctx.regs.setR8(r8, new_val);
    ctx.regs.setFlag(.Z, new_val == 0);
    ctx.regs.setFlag(.N, true);
    ctx.regs.setFlag(.H, (val & 0x0F) < (1 & 0x0F));
}

/// 00[r8]110[imm8]: LD r8, imm8: Copy the value imm8 into register r8
///
/// Cycles: 2
/// Bytes: 2
fn LD_r8_imm8(ctx: Context) void {
    const r8 = (ctx.opcode() >> 3) & 0b111;
    const imm8 = ctx.getImm8();

    ctx.regs.setR8(r8, imm8);
    ctx.pc.* += 1;
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
fn RLCA(ctx: Context) void {
    const carry = ctx.regs.A >> 7;

    ctx.regs.A = std.math.rotl(u8, ctx.regs.A, 1);
    ctx.regs.setFlag(.Z, false);
    ctx.regs.setFlag(.N, false);
    ctx.regs.setFlag(.H, false);
    ctx.regs.setFlag(.C, carry == 1);
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
fn RRCA(ctx: Context) void {
    const carry = ctx.regs.A & 0b00000001;

    ctx.regs.A = std.math.rotr(u8, ctx.regs.A, 1);
    ctx.regs.setFlag(.Z, false);
    ctx.regs.setFlag(.N, false);
    ctx.regs.setFlag(.H, false);
    ctx.regs.setFlag(.C, carry == 1);
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
fn RLA(ctx: Context) void {
    const old_carry = @intFromBool(ctx.regs.getFlag(.C));
    const new_carry = (ctx.regs.A >> 7) & 0b1;

    ctx.regs.A = (ctx.regs.A << 1) | old_carry;
    ctx.regs.setFlag(.Z, false);
    ctx.regs.setFlag(.N, false);
    ctx.regs.setFlag(.H, false);
    ctx.regs.setFlag(.C, new_carry == 1);
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
fn RRA(ctx: Context) void {
    const old_carry: u8 = @intFromBool(ctx.regs.getFlag(.C));
    const new_carry = ctx.regs.A & 0b1;
    ctx.regs.A = (ctx.regs.A >> 1) | (old_carry << 7);
    ctx.regs.setFlag(.Z, false);
    ctx.regs.setFlag(.N, false);
    ctx.regs.setFlag(.H, false);
    ctx.regs.setFlag(.C, new_carry == 1);
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
fn DAA(ctx: Context) void {
    var adjustment: u8 = 0;
    if (ctx.regs.getFlag(.N)) {
        if (ctx.regs.getFlag(.H)) {
            adjustment += 0x6;
        }
        if (ctx.regs.getFlag(.C)) {
            adjustment += 0x60;
        }
        ctx.regs.A -%= adjustment;
    } else {
        if (ctx.regs.getFlag(.H) or (ctx.regs.A & 0xF) > 0x9) {
            adjustment += 0x6;
        }
        if (ctx.regs.getFlag(.C) or (ctx.regs.A) > 0x99) {
            adjustment += 0x60;
            ctx.regs.setFlag(.C, true);
        }
        ctx.regs.A +%= adjustment;
    }

    ctx.regs.setFlag(.Z, ctx.regs.A == 0);
    ctx.regs.setFlag(.H, false);
}

/// 00101111: CPL: ComPLement accumulator (A = ~A) (bitwise NOT)
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=1
///     H=1
fn CPL(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 00110111: SCF: Set Carry Flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=0
///     H=0
///     C=1
fn SCF(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 00111111: CCF: Complement Carry Flag
///
/// Cycles: 1
/// Bytes: 1
/// Flags:
///     N=0
///     H=0
///     C=Inverted
fn CCF(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 00011000[imm8]: jr imm8: Relative Jump to address imm8 (SP + imm8)
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3
/// Bytes: 2
fn JR_imm8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 001[cond]000[imm8]: JR cond, imm8: Relative Jump to address imm8
/// (SP + imm8) if condition cond is met.
/// Address is encoded as signed 8-bit offset from address immediately
/// following the JR instruction.
///
/// Cycles: 3 taken / 2 untaken
/// Bytes: 2
fn JR_cond_imm8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 00010000: STOP: What happens depends on the state of the emulator. Refer to
/// this picture for details: https://gbdev.io/pandocs/imgs/stop_diagram.svg
///
/// Cycles: -
/// Bytes: 2 (depends on emulator state)
fn STOP(ctx: Context) void {
    _ = ctx;
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
fn LD_r8_r8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
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
fn HALT(ctx: Context) void {
    _ = ctx;
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
fn ADD_A_r8(ctx: Context) void {
    _ = ctx;
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
fn ADC_A_r8(ctx: Context) void {
    _ = ctx;
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
fn SUB_A_r8(ctx: Context) void {
    _ = ctx;
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
fn SBC_A_r8(ctx: Context) void {
    _ = ctx;
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
fn AND_A_r8(ctx: Context) void {
    _ = ctx;
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
fn XOR_A_r8(ctx: Context) void {
    _ = ctx;
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
fn OR_A_r8(ctx: Context) void {
    _ = ctx;
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
fn CP_A_r8(ctx: Context) void {
    _ = ctx;
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
fn ADD_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn ADC_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn SUB_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn SBC_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn AND_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn XOR_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn OR_A_imm8(ctx: Context) void {
    _ = ctx;
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
fn CP_A_imm8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 110[cond]000: RET cond: Return from subroutine if condition cond is met.
///
/// Cycles: 5 taken / 2 untaken
/// Bytes: 1
fn RET_cond(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11001001: RET: Return from subroutine. This is basically a POP PC.
///
/// Cycles: 4
/// Bytes: 1
fn RET(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11011001: RETI: Return from interrupt and enable interrupts. This is
/// basically a POP PC followed by setting the IME flag to 1
/// (EI followed by RET).
///
/// Cycles: 4
/// Bytes: 1
fn RETI(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 110[cond]010[imm16]: JP cond, imm16: Jump to address imm16 if condition
/// cond is met.
///
/// Cycles: 4 taken / 3 untaken
/// Bytes: 3
fn JP_cond_imm16(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11000011[imm16]: JP imm16: Jump to address imm16 (copy n16 into PC).
///
/// Cycles: 4
/// Bytes: 3
fn JP_imm16(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11101001: JP HL: Jump to address in HL (copy HL into PC).
///
/// Cycles: 1
/// Bytes: 1
fn JP_HL(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 110[cond]100: CALL cond, imm16: Call address imm16 if condition cond is met
///
/// Cycles: 6 taken / 3 untaken
/// Bytes: 3
fn CALL_cond_imm16(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11001101[imm16]: CALL imm16: Call address imm16. This pushes the address
/// of the instruction adter the CALL on the stack, such that RET can pop it
/// later; then, it executes an implicit JP imm16
///
/// Cycles: 6
/// Bytes: 3
fn CALL_imm16(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11[tgt3]111: RST tgt3: Call to address tgt3*8
///
/// Cycles: 4
/// Bytes: 1
fn RST_tgt3(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11[r16stk]0001: POP r16stk: Pop register r16stk off the stack
///
/// Cycles: 3
/// Bytes: 1
fn POP_r16stk(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11[r16stk]0101: PUSH r16stk: Push register r16stk onto the stack
///
/// Cycles: 4
/// Bytes: 1
fn PUSH_r16stk(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// $CB prefix. The next executed instruction is from the $CB bank portion of
/// the decode ROM. $CB prefix opcodes behave like two-byte opcodes
fn CB_prefix(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11100010: LDH [c], A: Store value of register A into byte at address
/// $FF00 + C
///
/// Cycles: 2
/// Bytes: 1
fn LDH_c_A(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// TRUTH UNKNOWN
/// 11100000[imm8]: LDH [imm8], A: Store value of register A into byte at
/// address $FF00 + imm8
///
/// Cycles: 3
/// Bytes: 2
fn LDH_imm8_A(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11101010[imm16]: LD [imm16], A: Copy the value of register A into the byte
/// at address imm16
///
/// Cycles: 4
/// Bytes: 3
fn LD_imm16_A(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11110010: LDH A, [c]: Copy the byte at address $FF00 + C into register A
///
/// Cycles: 2
/// Bytes: 1
fn LDH_A_c(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// TRUTH UNKNOWN
/// 11110000[imm8]: LDH A, [imm8]: Copy the byte at address $FF00 + imm8
/// into register A
///
/// Cycles: 3
/// Bytes: 2
fn LDH_A_imm8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11111010[imm16]: LD A, [imm16]: Load value at address imm16 into register A
///
/// Cycles: 4
/// Bytes: 3
fn LD_A_imm16(ctx: Context) void {
    _ = ctx;
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
fn ADD_SP_imm8(ctx: Context) void {
    _ = ctx;
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
fn LD_HL_SPimm8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11111001: LD A, HL: Copy register HL into stack pointer SP
///
/// Cycles: 2
/// Bytes: 1
fn LD_SP_HL(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11110011: DI: Disable Interrupts (IME = 0)
///
/// Cycles: 1
/// Bytes: 1
fn DI(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11111011: EI: Enable Interrupts (IME = 1)
/// The flag is only set after the instruction following EI
///
/// Cycles: 1
/// Bytes: 1
fn EI(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

// ------------------------------- end block 3 --------------------------------
// -------------------------- block 4: Opcode holes ---------------------------

/// these opcodes are not implemented and hard-lock the CPU until the console
/// is powered off: 0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC,
/// and 0xFD
fn Opcode_hole(ctx: Context) void {
    _ = ctx;
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
fn RLC_r8(ctx: Context) void {
    _ = ctx;
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
fn RRC_r8(ctx: Context) void {
    _ = ctx;
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
fn RL_r8(ctx: Context) void {
    _ = ctx;
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
fn RR_r8(ctx: Context) void {
    _ = ctx;
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
fn SLA_r8(ctx: Context) void {
    _ = ctx;
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
fn SRA_r8(ctx: Context) void {
    _ = ctx;
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
fn SWAP_r8(ctx: Context) void {
    _ = ctx;
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
fn SRL_r8(ctx: Context) void {
    _ = ctx;
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
fn BIT_b3_r8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 10[b3][r8]: RES b3, r8: Set bit b3 in register r8 to 0. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2
/// Bytes: 2
fn RES_b3_r8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

/// 11[b3][r8]: SET b3, r8: Set bit b3 in register r8 to 1. Bit 0 is the
/// rightmost one, bit 7 the leftmost one
///
/// Cycles: 2
/// Bytes: 2
fn SET_b3_r8(ctx: Context) void {
    _ = ctx;
    @panic("not implemented");
}

test "NOP" {
    var cpu = CPU.init();
    // setup fake RAM
    var RAM: [0x8000]u8 = @splat(0);
    // Set up a context with a NOP instruction at the current PC
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.PC == 1);
}

test "LD_r16_imm16" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    RAM[0] = 0b00000001; // Opcode for LD BC, imm16
    RAM[1] = 0x34; // Low byte
    RAM[2] = 0x12; // High byte
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.B == 0x34); // Low byte
    try std.testing.expect(cpu.registers.C == 0x12); // High byte
    try std.testing.expect(cpu.registers.PC == 3);
    RAM[3] = 0b00110001; // Opcode for LD SP, imm16
    RAM[4] = 0x78; // Low byte
    RAM[5] = 0x56; // High byte
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.SP == 0x7856);
    try std.testing.expect(cpu.registers.PC == 6);
}

test "LD_r16mem_A" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0xAB; // A register
    RAM[0] = 0b00000010; // Opcode for LD (BC), A
    cpu.registers.B = 0x34; // B register (high byte of BC)
    cpu.registers.C = 0x12; // C register (low byte of BC)
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(RAM[0x3412] == 0xAB);
    try std.testing.expect(cpu.registers.PC == 1);

    RAM[1] = 0b00100010; // Opcode for LD (HLI), A
    cpu.registers.H = 0x56; // H register (high byte of HL)
    cpu.registers.L = 0xFF; // L register (low byte of HL)
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(RAM[0x56FF] == 0xAB);
    try std.testing.expect(cpu.registers.H == 0x57);
    try std.testing.expect(cpu.registers.L == 0x00);
    try std.testing.expect(cpu.registers.PC == 2);
    RAM[2] = 0b00110010; // Opcode for LD (HLD), A
    cpu.registers.H = 0x4A; // H register (high byte of HL)
    cpu.registers.L = 0xBC; // L register (low byte of HL)
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(RAM[0x4ABC] == 0xAB);
    try std.testing.expect(cpu.registers.H == 0x4A);
    try std.testing.expect(cpu.registers.L == 0xBB);
    try std.testing.expect(cpu.registers.PC == 3);
}

test "LD_A_r16mem" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    RAM[0x3412] = 0xCD;
    RAM[0] = 0b00001010; // Opcode for LD A, (BC)
    cpu.registers.B = 0x34; // B register (high byte of BC)
    cpu.registers.C = 0x12; // C register (low byte of BC)
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0xCD); // A register
    try std.testing.expect(cpu.registers.PC == 1);
}

test "LD_imm16_SP" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.SP = 0x9ABC;
    RAM[0] = 0b00001000; // Opcode for LD (imm16), SP
    RAM[1] = 0x10; // Low byte of imm16
    RAM[2] = 0x80; // High byte of imm16
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(RAM[0x1080] == 0xBC); // Low byte of SP
    try std.testing.expect(RAM[0x1081] == 0x9A); // High byte of SP
    try std.testing.expect(cpu.registers.PC == 3);
}

test "INC_r16" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.B = 0xFF; // B register
    cpu.registers.C = 0xFF; // C register
    RAM[0] = 0b00000011; // Opcode for INC BC
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.B == 0x00); // B register
    try std.testing.expect(cpu.registers.C == 0x00); // C register
    try std.testing.expect(cpu.registers.PC == 1);

    cpu.registers.SP = 0x1234; // SP
    RAM[1] = 0b00110011; // Opcode for INC SP
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.SP == 0x1235); // SP
    try std.testing.expect(cpu.registers.PC == 2);
}

test "DEC_r16" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.B = 0x00; // B register
    cpu.registers.C = 0x00; // C register
    RAM[0] = 0b00001011; // Opcode for DEC BC
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.B == 0xFF); // B register
    try std.testing.expect(cpu.registers.C == 0xFF); // C register
    try std.testing.expect(cpu.registers.PC == 1);

    cpu.registers.SP = 0x0000; // SP
    RAM[1] = 0b00111011; // Opcode for DEC SP
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.SP == 0xFFFF); // SP
    try std.testing.expect(cpu.registers.PC == 2);
}

test "ADD_HL_r16" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.H = 0x1F; // H register
    cpu.registers.L = 0x34; // L register
    cpu.registers.B = 0x01; // B register
    cpu.registers.C = 0x10; // C register
    RAM[0] = 0b00001001; // Opcode for ADD HL, BC
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.H == 0x20);
    try std.testing.expect(cpu.registers.L == 0x44);
    try std.testing.expect(cpu.registers.F == 0b00100000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);

    cpu.registers.F = 0b10100000;
    cpu.registers.H = 0xFF; // H register
    cpu.registers.L = 0xFF; // L register
    cpu.registers.D = 0x00; // D register
    cpu.registers.E = 0x01; // E register
    RAM[1] = 0b00011001; // Opcode for ADD HL, DE
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.H == 0x00);
    try std.testing.expect(cpu.registers.L == 0x00);
    try std.testing.expect(cpu.registers.F == 0b10110000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 2);
}

test "INC_r8" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0xFF; // A register
    RAM[0] = 0b00111100; // Opcode for INC A
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0x00); // A register
    try std.testing.expect(cpu.registers.F == 0b10100000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);
}

test "DEC_r8" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0x00; // A register
    RAM[0] = 0b00111101; // Opcode for DEC A
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0xFF); // A register
    try std.testing.expect(cpu.registers.F == 0b01100000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);
}

test "LD_r8_imm8" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    RAM[0] = 0b00000110; // Opcode for LD B, imm8
    RAM[1] = 0x7A; // imm8 value
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.B == 0x7A); // B register
    try std.testing.expect(cpu.registers.PC == 2);
}

test "RLCA" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0b10000001; // A register
    RAM[0] = 0b00000111; // Opcode for RLCA
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0b00000011); // A register
    try std.testing.expect(cpu.registers.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);
}

test "RRCA" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0b00000011; // A register
    RAM[0] = 0b00001111; // Opcode for RRCA
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0b10000001); // A register
    try std.testing.expect(cpu.registers.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);
}

test "RLA" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0b10000001; // A register
    cpu.registers.F = 0b00010000; // Set Carry flag
    RAM[0] = 0b00010111; // Opcode for RLA
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0b00000011); // A register
    try std.testing.expect(cpu.registers.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);
}

test "RRA" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0b00000011; // A register
    cpu.registers.F = 0b00010000; // Set Carry flag
    RAM[0] = 0b00011111; // Opcode for RRA
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0b10000001); // A register
    try std.testing.expect(cpu.registers.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);
}

test "DAA" {
    var cpu = CPU.init();
    var RAM: [0x8000]u8 = @splat(0);
    cpu.registers.A = 0x98; // A register
    cpu.registers.F = 0b01110000; // Clear all flags
    RAM[0] = 0b00100111; // Opcode for DAA
    const ctx = Context{
        .RAM = &RAM,
        .regs = &cpu.registers,
        .pc = &cpu.registers.PC,
        .sp = &cpu.registers.SP,
    };
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0x98 - 0x66);
    try std.testing.expect(cpu.registers.F == 0b01010000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 1);

    cpu.registers.A = 0x12; // A register
    cpu.registers.F = 0b00110000; // Set N flag
    RAM[1] = 0b00100111; // Opcode for DAA
    cpu.execute(ctx);
    ctx.pc.* += 1;
    try std.testing.expect(cpu.registers.A == 0x12 + 0x66);
    try std.testing.expect(cpu.registers.F == 0b00010000); // Check Flags
    try std.testing.expect(cpu.registers.PC == 2);
}
