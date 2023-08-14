const pfn = @import("pfn.zig");

const PageSize = 4096; // Adjust as per your system's page size

pub const Slab = struct {
    const Self = @This();

    page_size: usize = PageSize,
    object_size: usize,
    objects_per_page: usize,
    free_list: ?*u8,


    pub fn init_slab(object_size: usize) Slab {
        return Slab {
            .page_size = PageSize,
            .object_size = object_size,
            .objects_per_page = PageSize / object_size,
            .free_list = undefined
        };
    }

    pub fn allocate(self: Self) ?*u8 {
        if (self.free_list != null) {
            const obj = self.free_list;
            self.free_list = *(obj.*.?*u8);
            return obj;
        } else {
            // Allocate a new page
            const page = align_page_alloc(self.page_size) catch {
                return null;
            };

            // Create a free list from the new page
            const page_start = @ptrCast(*u8, page);
            for (self.objects_per_page.reverse()) |i| {
                const obj = page_start + (i * self.object_size);
                (obj.*.?*u8) = *self.free_list;
                self.free_list = obj;
            }

            return self.free_list;
        }
    }

    pub fn deallocate(self: Self, obj: *u8) void {
        (obj.*.?*u8) = *self.free_list;
        self.free_list = obj;
    }

    pub fn align_page_alloc(size: usize) ?*u8 {
        var mem: [PageSize]u8 = pfn.AllocatePage(pfn.PFNType.Free, false, size);
        return mem.ptr;
    }
};