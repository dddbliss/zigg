const limine = @import("limine");
const std = @import("std");
const graphics = @import("graphics.zig");
const serial = @import("devices/serial.zig");
const gdt = @import("cpu/gdt.zig");
const idt = @import("cpu/idt.zig");
const apic = @import("cpu/apic.zig");
const acpi = @import("cpu/acpi.zig");
const mem = @import("memory.zig");
const slab = @import("memory/paging/slab.zig");
const pci = @import("devices/pci.zig");
const sata = @import("devices/sata.zig");
const vfs = @import("fs/vfs.zig");

pub export var framebuffer_request: limine.FramebufferRequest = .{};
var tty: serial.Serial = undefined;
pub var stdout: graphics.TextFrame = undefined;
pub var kslab: slab.Slab = slab.Slab.init_slab(4096);

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

fn memmapType(entry: *limine.MemoryMapEntry) []const u8 {
    return switch (entry.kind) {
        .acpi_nvs => "acpi",
        .acpi_reclaimable => "acpi",
        .bad_memory => "bad_memory",
        .bootloader_reclaimable => "bootloader",
        .framebuffer => "framebuffer",
        .kernel_and_modules => "kernel",
        .reserved => "reserved",
        .usable => "usable",
    };
}

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure we got a framebuffer.
    tty = serial.Serial.init();
    
    const framebuffer_response = framebuffer_request.response.?;

    if (framebuffer_response.framebuffer_count < 1) {
        @panic("NOOOOO");
        //done();
    }

    // Get the first framebuffer's information.
    const framebuffer = framebuffer_response.framebuffers()[0];

    const frame = graphics.Frame{ .info = framebuffer, .frame_buffer = framebuffer.address };

    var fg = graphics.Pixel{
        .blue = 255,
        .green = 255,
        .red = 255,
    };
    const bg = graphics.Pixel{
        .blue = 0,
        .green = 0,
        .red = 0,
    };

    stdout = graphics.TextFrame.init(frame, fg, bg);
    stdout.print("Hello OS from {s}!\n", .{"Zigg"});

    gdt.init();
    stdout.print("[info] Global Discriptor Table has been initialized.\n", .{});
    idt.initialize();
    stdout.print("[info] Interrupt Discriptor Table has been initialized.\n", .{});
    //stdout.print("Memory Map:\n", .{});

    //for (memmap_response.entries()) |entry| stdout.print(" - {d: >4.2}mb at {s: <12} at 0x{X:0<10} to 0x{X:0<10}\n", .{ @divTrunc(entry.length / 8, 1000 * 1000), memmapType(entry), entry.base, entry.base + entry.length });
    mem.init();

    acpi.initialize();
    apic.setup();

    stdout.print("-- PCI devices: \n", .{});
    try pci.scan_pci_devices();

    stdout.print("-- SATA/ATA devices: \n", .{});
    sata.scan_ata_devices();
    sata.scan_sata_devices();

    stdout.print("VFS:\n", .{});
    const kVfs = vfs.VFS.init_vfs();
    
    var file1 = kVfs.create_node("file.txt", false, vfs.NodeCallbacks {
            .read = fn (buffer: []u8, size: usize) usize {
                return "Hello from file 1.txt"
            },
            .write = undefined,
            .create = undefined,
            .delete = undefined
        }
    );

    var out = "";
    kVfs.read_node(file1, out, 6);
    stdout.print("file.txt says: {s}", out);

    idt.startInterrupts();
    tty.print("at the end", .{}) catch unreachable;
    // We're done, just hang...

    stdout.print("\n\n...now we wait", .{});

    done();
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, size: ?usize) noreturn {
    @setCold(true);
    _ = size;
    _ = error_return_trace;
    tty.print("[PANIC]: {s}\n", .{msg}) catch unreachable;
    done();
}
