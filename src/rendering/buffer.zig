const std = @import("std");
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;

const Context = @import("../context.zig").Context;

pub const Buffer = struct {
    buffer: *wl.Buffer,
    width: u64,
    height: u64,
    pixels: [*]u32,
    pixel_count: usize,

    pub fn new(width: u64, height: u64, context: *Context) anyerror!Buffer {
        const stride = width * 4;
        const size = stride * height;

        const fd = try posix.memfd_create("als-window", 0);
        try posix.ftruncate(fd, size);

        const data = try posix.mmap(
            null,
            size,
            posix.PROT.READ | posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );

        const pixels: [*]u32 = @ptrCast(@alignCast(data.ptr));
        const pixel_count = size / 4;
        @memset(pixels[0..pixel_count], 0xFF000000); // ARGB Black

        const pool = try context.wayland.shm.?.createPool(fd, @as(i32, @intCast(size)));
        defer pool.destroy();

        const buffer = try pool.createBuffer(0, @as(i32, @intCast(width)), @as(i32, @intCast(height)), @as(i32, @intCast(stride)), wl.Shm.Format.argb8888);

        return Buffer{
            .buffer = buffer,
            .width = width,
            .height = height,
            .pixels = pixels,
            .pixel_count = pixel_count,
        };
    }

    pub fn deinit(self: *Buffer) void {
        const size = self.width * self.height * 4;
        posix.munmap(@as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(self.pixels)))[0..size]);
        self.buffer.destroy();
    }

    pub fn set_pixel(self: *Buffer, x: u32, y: u32, color: u32) void {
        self.pixels[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))] = color; 
    }
};
