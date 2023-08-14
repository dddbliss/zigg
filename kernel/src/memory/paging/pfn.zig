const mem = @import("../../memory.zig");
const std = @import("std");
const idt = @import("../../cpu/idt.zig");
const spin = @import("../../spinlock.zig");

pub var pfnDatabase: []PFNEntry = undefined;
pub var pfnFreeHead: ?*PFNEntry = null;
pub var pfnZeroedHead: ?*PFNEntry = null;
pub var pfnSpinlock: spin.Spinlock = .unaquired;

pub const PFNType = enum(u3) {
    Free = 0,
    Zeroed = 1,
    Reserved = 2,
    Active = 3,
    PageTable = 4,
};

// PFN Database
pub const PFNEntry = struct {
    next: ?*PFNEntry = null,
    refs: u28 = 0,
    state: PFNType = .Free,
    swappable: u1 = 0,
    pte: usize,
};

pub fn Initialize(begin: usize, entryCount: usize, ranges: *[32]mem.PhysicalRange) void {
    pfnDatabase = @ptrFromInt([*]PFNEntry, begin)[0..entryCount];
    for (0..pfnDatabase.len) |i| {
        pfnDatabase[i].next = null;
        pfnDatabase[i].refs = 0;
        pfnDatabase[i].state = .Reserved;
        pfnDatabase[i].pte = 0;
    }
    for (ranges) |r| {
        var i = r.start;
        while (i < r.end) : (i += 4096) {
            pfnDatabase[i >> 12].next = pfnFreeHead;
            pfnDatabase[i >> 12].refs = 0;
            pfnDatabase[i >> 12].state = .Free;
            pfnFreeHead = &pfnDatabase[i >> 12];
        }
    }
}

pub fn AllocatePage(tag: PFNType, swappable: bool, pte: usize) ?[]u8 {
    idt.stopInterrupts();
    pfnSpinlock.acquire();
    if (pfnZeroedHead) |entry| {
        const phys: usize = ((@intFromPtr(entry) - @intFromPtr(pfnDatabase.ptr)) / @sizeOf(PFNEntry)) << 12;
        if (entry.state != .Zeroed) {
            @panic("paging system corrupted.");
        }
        pfnZeroedHead = entry.next;
        entry.next = null;
        entry.refs = if (tag == .PageTable) 0 else 1;
        entry.state = tag;
        entry.swappable = if (swappable) 1 else 0;
        entry.pte = pte;
        var ret = @ptrFromInt([*]u8, phys + 0xFFFF800000000000)[0..4096];
        pfnSpinlock.release();
        idt.startInterrupts();
        return ret;
    } else if (pfnFreeHead) |entry| {
        const phys: usize = ((@intFromPtr(entry) - @intFromPtr(pfnDatabase.ptr)) / @sizeOf(PFNEntry)) << 12;
        if (entry.state != .Free) {
            @panic("paging failed");
        }
        pfnFreeHead = entry.next;
        entry.next = null;
        entry.refs = if (tag == .PageTable) 0 else 1;
        entry.state = tag;
        entry.swappable = if (swappable) 1 else 0;
        entry.pte = pte;
        var ret = @ptrFromInt([*]u8, phys + 0xFFFF800000000000)[0..4096];
        @memset(ret, 0); // Freed Pages haven't been zeroed yet so we'll manually do it.
        pfnSpinlock.release();
        idt.startInterrupts();
        return ret;
    }
    pfnSpinlock.release();
    idt.startInterrupts();
    return null;
}

pub fn ReferencePage(page: usize) void {
    const index: usize = (page >> 12);
    idt.stopInterrupts();
    pfnSpinlock.acquire();
    pfnDatabase[index].refs += 1;
    pfnSpinlock.release();
    idt.startInterrupts();
}

pub fn DereferencePage(page: usize) void {
    const index: usize = (page >> 12);
    idt.stopInterrupts();
    pfnSpinlock.acquire();
    if (pfnDatabase[index].state != .Reserved) {
        pfnDatabase[index].refs -= 1;
        if (pfnDatabase[index].refs == 0) {
            const oldState = pfnDatabase[index].state;
            pfnDatabase[index].state = .Free;
            pfnDatabase[index].next = pfnFreeHead;
            pfnDatabase[index].swappable = 0;
            if (pfnDatabase[index].pte != 0 and oldState == .PageTable) {
                const entry: usize = pfnDatabase[index].pte;
                const pt = entry & (~@intCast(usize, 0xFFF));
                if (pfnDatabase[pt >> 12].state != .PageTable) {
                    @panic("page file dereference error");
                }
                @ptrFromInt(*usize, entry).* = 0;
                pfnFreeHead = &pfnDatabase[index];
                pfnSpinlock.release();
                DereferencePage(pt);
                idt.startInterrupts();
                return;
            } else {
                pfnFreeHead = &pfnDatabase[index];
            }
        }
    }
    pfnSpinlock.release();
   idt.startInterrupts();
}

pub fn ChangePTEEntry(page: usize, pte: usize) void {
    const index: usize = (page >> 12);
    idt.stopInterrupts();
    pfnSpinlock.acquire();
    pfnDatabase[index].pte = pte;
    pfnSpinlock.release();
    idt.startInterrupts();
}