const std = @import("std");
const min = std.math.min;
const limine = @import("limine");

pub const Pixel = struct { red: u8, blue: u8, green: u8 };

pub const Frame = struct {
    info: *limine.Framebuffer,
    frame_buffer: [*]u8,

    fn getPixel(self: *Frame, x: usize, y: usize) Pixel {
        _ = y;
        _ = x;
        _ = self;
        // TODO
        return Pixel{ .red = 0, .blue = 0, .green = 0 };
    }

    fn drawPixel(self: *Frame, pixel: Pixel, x: usize, y: usize) void {
        const start = (y * self.info.pitch + x * 4);
        const fb_pixel = self.frame_buffer[start .. start + 4];

        fb_pixel[0] = pixel.red;
        fb_pixel[1] = pixel.green;
        fb_pixel[2] = pixel.blue;
    }
};

var buf: [0x100000]u8 = undefined;

pub const TextFrame = struct {
    frame: Frame,
    foreground: Pixel,
    background: Pixel,

    cursor_x: u32,
    cursor_y: u32,
    max_x: u32,
    max_y: u32,

    const Self = @This();

    pub fn init(frame: Frame, foreground: Pixel, background: Pixel) TextFrame {
        var retval = TextFrame{
            .frame = frame,
            .foreground = foreground,
            .background = background,
            .cursor_x = 0,
            .cursor_y = 0,
            .max_x = @intCast(u32, frame.info.width) / (unifont_width),
            .max_y = @intCast(u32, frame.info.height) / (unifont_height),
        };
        if (retval.max_x != 0) {
            retval.max_x -= 1;
        }
        if (retval.max_y != 0) {
            retval.max_y -= 1;
        }

        return retval;
    }

    pub fn print(self: *Self, comptime format: []const u8, args: anytype) void {
        self.putChar(std.fmt.bufPrint(buf[0..], format, args) catch unreachable) catch unreachable;
    }

    fn drawChar(self: *Self, char: u8) void {
        for (unifont[char], 0..) |line, i| {
            for (line, 0..) |pixel, j| {
                self.frame.drawPixel(if (pixel) self.foreground else self.background, self.cursor_x * unifont_width + j, self.cursor_y * unifont_height + i);
            }
        }
    }

    fn newLine(self: *Self) void {
        self.cursor_x = 0;
        if (self.cursor_y < self.max_y) {
            self.cursor_y += 1;
        } else {
            {
                var i = @intCast(u32, unifont_height);
                while (i < self.frame.info.height - unifont_height) : (i += 1) {
                    var j = @intCast(u32, 0);
                    while (j < self.frame.info.width) : (j += 1) {
                        const new = 4 * (i + j);
                        const old = 4 * ((unifont_height + i) * j);
                        var k = @intCast(u32, 0);
                        while (k < 4) : (k += 1) {
                            self.frame.frame_buffer[new + k] = self.frame.frame_buffer[old + k];
                        }
                    }
                }
            }

            {
                var i = @intCast(u32, (self.max_y * unifont_height));
                while (i < self.frame.info.width) : (i += 1) {
                    var j = @intCast(u32, 0);
                    while (j < self.frame.info.height) : (j += 1) {
                        self.frame.drawPixel(self.background, i, j);
                    }
                }
            }
        }
    }

    fn putChar(self: *Self, text: []const u8) error{}!void {
        for (text) |char| {
            switch (char) {
                '\r' => {
                    self.cursor_x = 0;
                },
                '\n' => {
                    self.newLine();
                },
                '\t' => {
                    for(0..3) |z| {
                        _ = z;
                        self.drawChar(' ');
                        self.cursor_x += 1;
                    }
                },
                '\x08' => {
                    self.cursor_x -= 1;
                    self.drawChar(' ');
                },
                else => {
                    if (self.cursor_x == self.max_x) {
                        self.newLine();
                    }
                    self.drawChar(char);
                    self.cursor_x += 1;
                },
            }
        }
    }
};

const unifont_width = 8;
const unifont_height = 16;
const unifont = init: {
    @setEvalBranchQuota(100000);

    const data = @embedFile("resource/zap-light16.psf")[4..];
    var retval: [256][16][8]bool = undefined;

    for (&retval, 0..) |*char, i| {
        for (char, 0..) |*line, j| {
            for (line, 0..) |*pixel, k| {
                pixel.* = data[i * 16 + j] & 0b10000000 >> k != 0;
            }
        }
    }

    break :init retval;
};
