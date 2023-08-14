const limine = @import("limine");
const std = @import("std");
const root = @import("root");
const paging = @import("memory/paging/paging.zig");
const pfn = @import("memory/paging/pfn.zig");

export var memmap_request: limine.MemoryMapRequest = .{};
export var kfile_request: limine.KernelFileRequest = .{};

pub const PhysicalRange = struct {
    start: u64,
    end: u64
};

pub fn init() void {
    var kfstart: usize = 0;
    var kfend: usize = 0;
    
    if (kfile_request.response) |response| {
        kfstart = @intFromPtr(response.kernel_file.address) - 0xffff800000000000;
        kfend = if ((response.kernel_file.size % 4096) != 0) (kfstart + ((response.kernel_file.size / 4096 + 1) * 4096)) else (kfstart + response.kernel_file.size);
    }

    var ranges: [32]PhysicalRange = [_]PhysicalRange{.{ .start = 0, .end = 0 }} ** 32;
    var m: usize = 0;
    if (memmap_request.response) |response| {
        for (response.entries()) |entry| {
            if (entry.kind == .usable) {
                ranges[m].start = entry.base;
                ranges[m].end = entry.base + entry.length;
                m += 1;
            }
        }
    }
    ranges[m].start = kfstart;
    ranges[m].end = kfend;

    var total_phys: u64 = 0;
    for (ranges) |range| {
        total_phys += range.end - range.start;
    }


    root.stdout.print("Found {d}mb physical memory available.\n", .{(2^(total_phys) * @sizeOf(u64) / (8) / 1024) / 1024});
    
    var initial: usize = asm volatile ("mov %%cr3, %[ret]"
        : [ret] "={rax}" (-> usize),
    ) + 0xffff800000000000;

    var initialPd = @ptrFromInt([*]usize, initial)[0..512];

    paging.initialPageDir = initialPd;
    var highestAddress: usize = 0x100000000;
    for (ranges) |r| {
        if (r.end > highestAddress) {
            highestAddress = r.end;
        }
    }
    const entries = highestAddress / 4096;
    const neededSize: usize = ((entries * @sizeOf(pfn.PFNEntry)) & (~@intCast(usize, 0xFFF))) + (if (((entries * @sizeOf(pfn.PFNEntry)) % 4096) > 0) 4096 - ((entries * @sizeOf(pfn.PFNEntry)) % 4096) else 0);
    var startAddr: usize = 0;
    for (ranges, 0..) |r, i| {
        if ((r.end - r.start) > neededSize) {
            startAddr = r.start + 0xffff800000000000;
            ranges[i].start += neededSize;
            break;
        } else if ((r.end - r.start) == neededSize) {
            startAddr = r.start + 0xffff800000000000;
            ranges[i].start = 0;
            ranges[i].end = 0;
            break;
        }
    }
    if (startAddr == 0) {
        @panic("pfn error");
    }
    root.stdout.print("Preparing PFN Database [{d} entries, {d} KiB, 0x{x:0>16}]...\n", .{ entries, neededSize / 1024, startAddr });
    pfn.Initialize(startAddr, entries, &ranges);

}