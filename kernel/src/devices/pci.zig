const std = @import("std");
const root = @import("root");
const io = @import("io.zig");

const PCI_CONFIG_ADDRESS: u16 = 0xCF8;
const PCI_CONFIG_DATA: u16 = 0xCFC;

pub const PCI_Device = struct {
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
    prog_if: u8,
    revision: u8,
};

fn get_vendor(vendor_id: u64) []const u8 {
    return switch(vendor_id) {
        0x8086 => "Intel Corporation",
        0x1234 => "QEMU",
        else => "Unknown"
    };
}

pub fn scan_pci_devices() !void {
    for (0..255) |bus| {
        for (0..31) |device| {
            for (0..7) |function| {
                const pci_config_address: u32 = @intCast(u32, (1 << 31) | (bus << 16) | (device << 11) | (function << 8));
                io.outl(0xCF8, pci_config_address);

                // Read the vendor ID and device ID
                const vendor_id = io.inl(0xCFC) & 0xFFFF;
                const device_id = io.inl(0xCFC) >> 16;

                // Check if a device is present
                if(vendor_id != 0xFFFF and device_id != 0xFFFF) {
                    // Read additional device information
                    const class_code = io.inl(0xCFC + 8) >> 24;
                    const subclass = io.inl(0xCFC + 8) >> 16 & 0xFF;
                    const prog_if = io.inl(0xCFC + 8) >> 8 & 0xFF;
                    const header_type = io.inl(0xCFC + 12) >> 16 & 0xFF;

                    root.stdout.print("Vendor: {s}, Device: 0x{x:4}, Class: 0x{x:2}, Subclass: 0x{x:2}, Program: 0x{x:2}, Header: 0x{x:2}\n", .{get_vendor(vendor_id), device_id, class_code, subclass, prog_if, header_type});
                }
            }
        }
    }
}