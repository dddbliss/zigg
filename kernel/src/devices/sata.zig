const io = @import("io.zig");
const root = @import("root");

pub fn scan_ata_devices() void {
    const PrimaryBasePort: u16 = 0x1F0;
    const SecondaryBasePort: u16 = 0x170;

    for (0..1) |port_idx| {

        var base_port = PrimaryBasePort;
        if (port_idx % 2 == 0) {
            base_port = PrimaryBasePort;
        } else {
            base_port = SecondaryBasePort;
        }

         // Select the controller by writing to the Device/Head register
        io.outb(base_port + 6, @intCast(u8,0xA0 | (port_idx % 2) << 4));

        // Read the signature bytes from the Command Block Registers
        const signature1 = io.inb(base_port + 3);
        const signature2 = io.inb(base_port + 4);

        // Check if the signature indicates a valid IDE controller
        if (signature1 == 0x14 and signature2 == 0xEB) {
            root.stdout.print("IDE Device found at port {d}\n", .{port_idx});
        }

        const status = io.inb(base_port + 7);
        if (status != 0xFF) {
            root.stdout.print("ATA Device found at port {d}\n", .{port_idx});
        }
    }
}

pub fn scan_sata_devices() void {
    for (0..7) |port_idx| {
        const base_port: u16 = 0x1F0 + (@intCast(u16, port_idx * 8));

        // Select the device by writing the port index to the control register
        io.outb(base_port + 6, @intCast(u8, port_idx << 4));

        // Read the status register to check if a device is present
        const status = io.inb(base_port + 7);
        if (status != 0xFF) {
            root.stdout.print("SATA Device found at port {d}\n", .{port_idx});
        }
    }
}