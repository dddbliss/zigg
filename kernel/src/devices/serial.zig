const std = @import("std");
const io = @import("io.zig");

var buffer: [0x100000]u8 = undefined;
var fbs = std.io.fixedBufferStream(&buffer);
var stream = fbs.writer();

pub const Serial = struct {
    const Self = @This();

    port: u16,

    pub fn init() Serial {
        var retval = Serial{
            .port = 0x03F8,
        };

        io.outb(retval.port + 1, 0x00); // Disable all interrupts
        io.outb(retval.port + 3, 0x80); // Enable DLAB (set baud rate divisor)
        io.outb(retval.port + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
        io.outb(retval.port + 1, 0x00); //                  (hi byte)
        io.outb(retval.port + 3, 0x03); // 8 bits, no parity, one stop bit
        io.outb(retval.port + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
        io.outb(retval.port + 4, 0x0B); // IRQs enabled, RTS/DSR set
        io.outb(retval.port + 4, 0x1E); // Set in loopback mode, test the serial chip
        io.outb(retval.port + 0, 0xAE); // Test serial chip (send byte 0xAE and check if serial returns same byte)

        io.outb(retval.port + 4, 0x0F);

        return retval;
    }

    fn sendChar(self: Self, chr: u8) !void {
        while ((io.inb(self.port + 5) & 0x20) == 0) {}
        io.outb(self.port, chr);
    }

    fn putString(self: Self, text: []const u8) void {
        for (text) |chr| {
            self.sendChar(chr) catch unreachable;
        }
    }

    pub fn print(self: Self, comptime format: []const u8, args: anytype) error{}!void {
        fbs.reset();
        std.fmt.format(stream, format, args) catch {};
        self.putString(fbs.getWritten());
    }
};
