const mem = @import("../../memory.zig");
const pfn = @import("pfn.zig");

pub const PageDirectory = []usize;

pub const MapRead = 1;
pub const MapWrite = 2;
pub const MapExec = 4;
pub const MapSupervisor = 8;
pub const MapNoncached = 16;
pub const MapWriteThru = 32;
pub const MapWriteComb = 64;

pub var initialPageDir: ?PageDirectory = null;

pub const PTEEntry = packed struct {
    r: u1 = 0,
    w: u1 = 0,
    x: u1 = 0,
    userSupervisor: u1 = 0,
    nonCached: u1 = 0,
    writeThrough: u1 = 0,
    writeCombine: u1 = 0,
    reserved: u5 = 0,
    phys: u52 = 0,
};

const NativePTEEntry = packed struct {
    valid: u1 = 0,
    write: u1 = 0,
    user: u1 = 0,
    writeThrough: u1 = 0,
    cacheDisable: u1 = 0,
    reserved1: u2 = 0,
    pat: u1 = 0,
    reserved2: u4 = 0,
    phys: u51 = 0,
    noExecute: u1 = 0,
};


pub fn GetPTE(root: *void, index: usize) PTEEntry {
    var entries: []align(1) NativePTEEntry = @ptrCast([*]align(1) NativePTEEntry, @alignCast(1, root))[0..512];
    var entry: PTEEntry = PTEEntry{};
    entry.r = entries[index].valid;
    entry.w = entries[index].write;
    entry.x = 1;
    entry.nonCached = entries[index].cacheDisable;
    entry.writeThrough = entries[index].writeThrough;
    entry.writeCombine = entries[index].pat;
    entry.phys = @intCast(u52, entries[index].phys);
    return entry;
}

pub fn SetPTE(root: *void, index: usize, entry: PTEEntry) void {
    var entries: []align(1) NativePTEEntry = @ptrCast([*]align(1) NativePTEEntry, @alignCast(1, root))[0..512];
    entries[index].valid = entry.r;
    entries[index].write = entry.w;
    entries[index].cacheDisable = entry.nonCached | entry.writeCombine;
    entries[index].writeThrough = entry.writeThrough | entry.writeCombine;
    entries[index].pat = entry.writeCombine;
    entries[index].phys = @intCast(u51, entry.phys & 0xfffffffff);
}

pub inline fn GetPTELevels() usize {
    return 4;
}

pub fn NewPageDirectory() PageDirectory {
    const page = pfn.AllocatePage(.PageTable, false, 0).?;
    pfn.ReferencePage(@intFromPtr(page.ptr) - 0xffff800000000000);
    var pageDir = @ptrCast([*]usize, @alignCast(@alignOf(usize), page.ptr))[0..512];
    var i: usize = 256;
    while (i < 512) : (i += 1) {
        pageDir[i] = initialPageDir.?[i];
    }
    return pageDir;
}

fn derefPageTable(pt: *void, level: usize) void {
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        if (level == 0 and i >= 256) {
            break;
        } else if (level + 1 >= GetPTELevels()) {
            const pte = GetPTE(pt, i);
            if (pte.r != 0) {
                const addr = @intCast(usize, pte.phys) << 12;
                pfn.DereferencePage(addr);
                SetPTE(pt, 0, PTEEntry{});
                pfn.DereferencePage(@intFromPtr(pt) - 0xffff800000000000);
            }
        } else {
            const pte = GetPTE(pt, i);
            if (pte.r != 0) {
                derefPageTable(@ptrFromInt(*void, @intCast(usize, pte.phys) << 12), level + 1);
            }
        }
    }
}

pub inline fn DestroyPageDirectory(root: PageDirectory) void {
    derefPageTable(@ptrCast(*void, root.ptr), 0);
}

pub fn MapPage(root: PageDirectory, vaddr: usize, flags: usize, paddr: usize) usize {
    const pte = PTEEntry{
        .r = @intCast(u1, flags & MapRead),
        .w = @intCast(u1, (flags >> 1) & 1),
        .x = @intCast(u1, (flags >> 2) & 1),
        .userSupervisor = @intCast(u1, (flags >> 3) & 1),
        .nonCached = @intCast(u1, (flags >> 4) & 1),
        .writeThrough = @intCast(u1, (flags >> 5) & 1),
        .writeCombine = @intCast(u1, (flags >> 6) & 1),
        .reserved = 0,
        .phys = @intCast(u52, paddr >> 12),
    };
    var i: usize = 0;
    var entries: *void = @ptrCast(*void, root.ptr);
    while (i < GetPTELevels()) : (i += 1) {
        const index: u64 = (vaddr >> (39 - @intCast(u6, i * 9))) & 0x1ff;
        var entry = GetPTE(entries, index);
        if (i + 1 >= GetPTELevels()) {
            if (pte.r == 0) {
                SetPTE(entries, index, PTEEntry{});
                pfn.DereferencePage(@intFromPtr(entries) - 0xffff800000000000);
                return @intFromPtr(entries) + (index * @sizeOf(pfn.PFNEntry));
            } else {
                SetPTE(entries, index, pte);
                pfn.ReferencePage(@intFromPtr(entries) - 0xffff800000000000);
                return @intFromPtr(entries) + (index * @sizeOf(pfn.PFNEntry));
            }
        } else {
            if (entry.r == 0) {
                // Allocate Page
                var page = pfn.AllocatePage(.PageTable, vaddr < 0x800000000000, @intFromPtr(entries) + (index * @sizeOf(usize))).?;
                entry.r = 1;
                entry.w = 1;
                entry.x = 0;
                entry.userSupervisor = pte.userSupervisor;
                entry.nonCached = 0;
                entry.writeThrough = 0;
                entry.writeCombine = 0;
                entry.phys = @intCast(u52, (@intFromPtr(page.ptr) - 0xffff800000000000) >> 12);
                SetPTE(entries, index, entry);
                pfn.ReferencePage(@intFromPtr(entries) - 0xffff800000000000);
                entries = @ptrFromInt(*void, @intFromPtr(page.ptr));
            } else {
                entries = @ptrFromInt(*void, (@intCast(usize, entry.phys) << 12) + 0xffff800000000000);
            }
        }
    }
    unreachable;
}

pub fn GetPage(root: PageDirectory, vaddr: usize) PTEEntry {
    var i: usize = 0;
    var entries: *void = @ptrCast(*void, root.ptr);
    while (i < GetPTELevels()) : (i += 1) {
        const index: u64 = (vaddr >> (39 - @intCast(u6, i * 9))) & 0x1ff;
        var entry = GetPTE(entries, index);
        if (i + 1 >= GetPTELevels()) {
            return entry;
        } else {
            if (entry.r == 0) {
                return PTEEntry{};
            } else {
                entries = @ptrFromInt(*void, (@intCast(usize, entry.phys) << 12) + 0xffff800000000000);
            }
        }
    }
    unreachable;
}

pub fn FindFreeSpace(root: PageDirectory, start: usize, size: usize) ?usize { // This is only used for the Static and Paged Pools, userspace doesn't use this
    var i = start;
    var address: usize = 0;
    var count: usize = 0;
    while (i < start + (512 * 1024 * 1024 * 1024)) : (i += 4096) {
        if (GetPage(root, i).r != 0) {
            count = 0;
            address = 0;
            continue;
        }
        if (address == 0)
            address = i;
        count += 4096;
        if (count >= size)
            return address;
    }
    return null;
}

pub const AccessRead = 1;
pub const AccessWrite = 2;
pub const AccessExecute = 4;
pub const AccessSupervisor = 8;
pub const AccessIsValid = 16;

pub fn PageFault(pc: usize, addr: usize, accessType: usize) void {
    _ = pc;
    if (accessType & AccessSupervisor != 0) {
        if (addr >= 0xfffffe8000000000 and addr <= 0xfffffeffffffffff) {
            @panic("page fault");
        } else {
            @panic("unhandled page fault");
        }
    }
}