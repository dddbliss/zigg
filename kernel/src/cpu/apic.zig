const std = @import("std");
const root = @import("root");
const acpi = @import("acpi.zig");

pub var lapic_ptr: usize = 0;
pub var ioapic_regSelect: *allowzero volatile u32 = @ptrFromInt(*allowzero volatile u32, 0);
pub var ioapic_ioWindow: *allowzero volatile u32 = @ptrFromInt(*allowzero volatile u32, 0);

const x2apic_register_base: usize = 0x800;

pub var ioapic_redirect: [24]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 };
pub var ioapic_activelow: [24]bool = [_]bool{false} ** 24;
pub var ioapic_leveltrig: [24]bool = [_]bool{false} ** 24;

pub fn rdmsr(index: u32) u64 {
    var low: u32 = 0;
    var high: u32 = 0;
    asm volatile ("rdmsr"
        : [lo] "={rax}" (low),
          [hi] "={rdx}" (high),
        : [ind] "{rcx}" (index),
    );
    return (@intCast(u64, high) << 32) | @intCast(u64, low);
}

pub fn wrmsr(index: u32, val: u64) void {
    var low: u32 = @intCast(u32, val & 0xFFFFFFFF);
    var high: u32 = @intCast(u32, val >> 32);
    asm volatile ("wrmsr"
        :
        : [lo] "{rax}" (low),
          [hi] "{rdx}" (high),
          [ind] "{rcx}" (index),
    );
}

pub fn setup() void {
    if (false) {
        lapic_ptr = 0xffffffff;
        root.stdout.print("X2APIC is enabled or required by system, switching to X2APIC operations\n", .{});

        wrmsr(0x1b, (rdmsr(0x1b) | 0x800 | 0x400)); // Enable the X2APIC
    } else {
        wrmsr(0x1b, (rdmsr(0x1b) | 0x800) & ~(@as(u64, 1) << @as(u64, 10))); // Enable the XAPIC

        lapic_ptr = (rdmsr(0x1b) & 0xfffff000) + 0xffff800000000000; // Get the Pointer

    }
    write(0x320, 0x10000);
    write(0xf0, 0x1f0); // Enable Spurious Interrupts (This starts up the Local APIC)
    // Next, we need to calibrate and enable the Local APIC Timer
    // (Note: The HPET can sometimes be less accurate than the PIT depending on the clock speed of the HPET.
    //        This is usually the base clock speed of the CPU, which when calculating the amount of cycles which 10 ms
    //        has passed can be less accure due to it not evenly dividing. The PIT on the other hand is guarenteed
    //        to closely hit 10 ms, though it does fall ~1 second behind/ahead per day (I think???))
    write(0x3e0, 0x3); // Set the timer to use divider 16
    // Prepare the HPET timer to wait for 10 ms
    var addr: usize = acpi.HPETAddr.?.address;
    const hpetAddr: [*]align(1) volatile u64 = @ptrFromInt([*]align(1) volatile u64, addr);
    var clock = hpetAddr[0] >> 32;
    hpetAddr[2] = 0;
    hpetAddr[32] = (hpetAddr[32] | (1 << 6)) & (~@intCast(u64, 0b100));
    hpetAddr[30] = 0;
    hpetAddr[2] = 1;
    const hz = @intCast(u64, 1000000000000000) / clock;
    var interval = (10 * (1000000000000 / clock));
    const val = (((hz << 16) / (interval)));

    root.stdout.print("HPET @ {d} Hz (~{d}.{d} Hz interval) for Local APIC Timer calibration\n", .{ hz, val >> 16, (10000 * (val & 0xFFFF)) >> 16 });

    write(0x380, 0xffffffff); // Set the Initial Count to 0xffffffff
    // Start the HPET or PIT timer and wait for it to finish counting down.
    const duration = hpetAddr[30] + interval;
    while (hpetAddr[30] < duration) {
        std.atomic.spinLoopHint();
    }
    write(0x320, 0x10000); // Stop the Local APIC Timer
    var ticks: u32 = 0xffffffff - @intCast(u32, read(0x390)); // We now have the number of ticks that elapses in 10 ms (with divider 16 of course)
    // Set the Local APIC timer to Periodic Mode, Divider 16, and to trigger every millisecond.
    write(0x3e0, 0x3);
    write(0x380, ticks / 10);
    write(0x320, 32 | 0x20000);
    // Now, we'll start to recieve interrupts from the timer!
    // This is vital for preemptive multitasking, and will be super useful for the kernel.
    // Now we'll setup the IO APIC
    for (0..24) |i| {
        if (ioapic_redirect[i] != 0 and ioapic_redirect[i] != 0xff and ioapic_redirect[i] != 8) {
            const val1: u64 = if (ioapic_leveltrig[i]) @intCast(u64, 1) << 15 else 0;
            const val2: u64 = if (ioapic_activelow[i]) @intCast(u64, 1) << 13 else 0;
            writeIo64(0x10 + (2 * i), (ioapic_redirect[i] + 0x20) | val1 | val2);
        }
    }
}

pub fn read(reg: usize) u64 {
    if (lapic_ptr == 0xffffffff) { // X2APIC
        return rdmsr(@intCast(u32, x2apic_register_base + (reg / 16)));
    } else {
        return @intCast(u64, @ptrFromInt(*volatile u32, lapic_ptr + reg).*);
    }
}

pub fn write(reg: usize, val: u64) void {
    if (lapic_ptr == 0xffffffff) { // X2APIC
        wrmsr(@intCast(u32, x2apic_register_base + (reg / 16)), val);
    } else {
        @ptrFromInt(*volatile u32, lapic_ptr + reg).* = @intCast(u32, val & 0xFFFFFFFF);
    }
}

pub fn readIo32(reg: usize) u32 {
    ioapic_regSelect.* = @intCast(u32, reg);
    return ioapic_ioWindow.*;
}

pub fn writeIo32(reg: usize, val: u32) void {
    ioapic_regSelect.* = @intCast(u32, reg);
    ioapic_ioWindow.* = val;
}

pub fn readIo64(reg: usize) u64 {
    const low: u64 = @intCast(u64, readIo32(reg));
    const high: u64 = @intCast(u64, readIo32(reg + 1)) << 32;
    return high | low;
}

pub fn writeIo64(reg: usize, val: u64) void {
    writeIo32(reg, @intCast(u32, val & 0xFFFFFFFF));
    writeIo32(reg + 1, @intCast(u32, (val >> 32) & 0xFFFFFFFF));
}
