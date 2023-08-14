const io = @import("../devices/io.zig");
const idt = @import("idt.zig");
const root = @import("root");
const apic = @import("apic.zig");
const std = @import("std");
pub fn stub() void {} // To ensure that the compiler will not optimize this module out.

pub export fn ExceptionHandler(entry: u8, con: *Context, errcode: u32) callconv(.C) void {
    _ = errcode;
    _ = con;
    if (entry == 0x8) {
        @panic("Global Fault");
    } else if (entry == 0xd) {
        @panic("Protection Fault");
    } else if (entry == 0xe) {
        @panic("Page Fault");
    } else if (entry == 0x2) {
        @panic("Non-maskable interrupt!");
    } else {
        @panic("No Idea... Uknown");
    }
}

pub var irqISRs: [224]?*const fn () callconv(.C) void = [_]?*const fn () callconv(.C) void{null} ** 224;

const KeyMap = struct {
    pub const ScanCode: [346]u8 = [346]u8{
        0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8,
        9, 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n', 0,
        'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, '\\',
        'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, 32, 0,
        0, 0, 0, 0, 0, 0, 0, '7', '8', '9', '-', '4', '5', '6', '+', '1',
        '2', '3', '0', '.', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };

    pub const ShiftScanCode: [253]u8 = [253]u8{
        0, 27, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '\x08',
        '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n', 0,
        'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|',
        'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0,
        0, 0, 0, 0, 0, 0, 0, '7', '8', '9', '-', '4', '5', '6', '+', '1',
        '2', '3', '0', '.', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
};

pub fn mapScanCodeToAscii(scanCode: u8, shift: bool) u8 {
    const keyMap = if (shift) KeyMap.ScanCode else KeyMap.ScanCode;
    if (scanCode >= keyMap.len) {
        return;
    }

    return keyMap[scanCode];
}

const BreakCode: u8 = 0x80;
const LeftShiftCode: u8 = 0x2A;
const RightShiftCode: u8 = 0x36;
const ReleaseLeftShiftCode: u8 = 0xAA;
const KeyGroup = struct {
    const Self = @This();

    keys: [2]u8,

    fn init(items: [2]u8) KeyGroup {
        var retval = KeyGroup {
            .keys = items
        };

        return retval;
    }

    fn contains(self: Self, item:u8) bool {
        for(self.keys) |key| {
            return if(key == item) true else continue;
        }

        return false;
    }
};

const ShiftKeys: KeyGroup = KeyGroup.init([2]u8 {0x2A, 0x36});
const ReleaseShiftKeys: KeyGroup = KeyGroup.init([2]u8 {0xAA, 0xB6});


var shiftPressed: bool = false;

fn processScanCode(scanCode: u8) u8 {
    var code = scanCode;
    if(scanCode & BreakCode != 0) {
        // It's a break code, so ignore it
        if(ReleaseShiftKeys.contains(scanCode)) {
            // Shift key released
            shiftPressed = false;
            return 0;
        }

        code = scanCode & (~BreakCode);
        return 0;
    }

    if(ShiftKeys.contains(scanCode)) {
        // Shift key pressed
        shiftPressed = true;
        return 0;
    }

    if(shiftPressed) {
        // Apply shift key mapping
        // You can add your own logic to handle special characters when Shift is pressed
        return KeyMap.ShiftScanCode[code];
    } else {
        // Non-shifted mapping
        return KeyMap.ScanCode[code];
    }
}

pub fn keyboard() callconv(.C) void {
    while (io.inb(0x64) & 1 == 0)
        return;

    var scanCode = io.inb(0x60);
    const keyCode = processScanCode(scanCode);
    if (keyCode != 0) {
        root.stdout.print("{c}", .{keyCode});
    }
}

// register irq.
pub fn attachIrq(irq: u16, routine: ?*const fn () callconv(.C) void) callconv(.C) u16 {
    root.stdout.print("Installing IRQ {d} to {*}\n", .{ irq, routine });
    irqISRs[irq] = routine;
    return irq;
}

pub const Context = packed struct {
    r15: u64 = 0,
    r14: u64 = 0,
    r13: u64 = 0,
    r12: u64 = 0,
    r11: u64 = 0,
    r10: u64 = 0,
    r9: u64 = 0,
    r8: u64 = 0,
    rbp: u64 = 0,
    rdi: u64 = 0,
    rsi: u64 = 0,
    rdx: u64 = 0,
    rcx: u64 = 0,
    rbx: u64 = 0,
    rax: u64 = 0,
    rip: u64 = 0,
    cs: u64 = 0,
    rflags: u64 = 0x202,
    rsp: u64 = 0,
    ss: u64 = 0,
};

pub export fn IRQHandler(entry: u8, con: *Context) callconv(.C) void {
    _ = con;
    //if(entry != 0x20) root.stdout.print("int {d}", .{entry});
    if (irqISRs[entry - 0x20]) |isr| {

        isr();
    }
     apic.write(0xb0, 0);
}
