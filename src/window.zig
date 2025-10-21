const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

pub const OutputInfo = struct {
    output: *wl.Output,
    width: i32 = 0,
    height: i32 = 0,
    ready: bool = false,
};

pub const WindowBuffer = struct {
    buffer: *wl.Buffer,
    pixels: [*]u32,
    pixel_count: usize,
};

pub const Callbacks = struct {
    leftpress: ?i32,
    leftrelease: ?i32,
    mouseenter: ?i32,
    mouseleave: ?i32,
    mousemotion: ?i32,
    key: ?i32,
};

pub const Window = struct {
    surface: *wl.Surface,
    layer_surface: *zwlr.LayerSurfaceV1,
    wBuffer: WindowBuffer,
    x: i32,
    y: i32,
    width: u64,
    height: u64,
    callbacks: Callbacks,

    pub fn init(
        window_name: []const u8,
        width: u64,
        height: u64,
        x: i32,
        y: i32,
        display: *wl.Display,
        compositor: *wl.Compositor,
        shm: *wl.Shm,
        layer_shell: *zwlr.LayerShellV1,
        output: *wl.Output,
    ) !Window {
        const wBuffer = blk: {
            const stride = width * 4;
            const size = stride * height;

            const fd = try posix.memfd_create(window_name, 0);
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
            @memset(pixels[0..pixel_count], 0xFF00FF00); // ARGB

            const pool = try shm.createPool(fd, @as(i32, @intCast(size)));
            defer pool.destroy();

            const buffer = try pool.createBuffer(
                       0,
                       @as(i32, @intCast(width)),
                       @as(i32, @intCast(height)),
                       @as(i32, @intCast(stride)),
                       wl.Shm.Format.argb8888
                   );

            break :blk WindowBuffer{
                .buffer = buffer,
                .pixels = pixels,
                .pixel_count = pixel_count,
            };
        };

        const surface = try compositor.createSurface();
        
        const region = try compositor.createRegion();
        region.add(0, 0, @intCast(width), @intCast(height));
        surface.setInputRegion(region);
        region.destroy();

        const layer_surface = try layer_shell.getLayerSurface(
            surface,
            output,
            zwlr.LayerShellV1.Layer.overlay,
            "cat"
        );

        layer_surface.setSize(@intCast(width), @intCast(height));
        layer_surface.setAnchor(.{
            .bottom = true,
            .left = true,
        });

        layer_surface.setKeyboardInteractivity(.on_demand);
        layer_surface.setMargin(0, 0, y, x); // top right bottom left

        var configured = false;
        layer_surface.setListener(*bool, layerSurfaceListener, &configured);
        surface.commit();

        while (!configured) {
            if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
        }

        surface.attach(wBuffer.buffer, 0, 0);
        surface.commit();

        const callbacks = Callbacks{
            .leftpress = null,
            .leftrelease = null,
            .mouseenter = null,
            .mouseleave = null,
            .mousemotion = null,
            .key = null,
        };

        return Window{
            .surface = surface,
            .layer_surface = layer_surface,
            .wBuffer = wBuffer,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .callbacks = callbacks,
        };
    }

    pub fn deinit(self: *Window) void {
        self.layer_surface.destroy();
        self.surface.destroy();
        self.wBuffer.buffer.destroy();
    }

    pub fn update(_: *Window, display: *wl.Display) anyerror!void {
        if (display.flush() != .SUCCESS) return error.FlushFailed;
    }

    pub fn setColor(self: *Window, color: u32) void {
        const pixels = self.wBuffer.pixels;
        const pixel_count = self.wBuffer.pixel_count;
        @memset(pixels[0..pixel_count], color); // ARGB
        self.surface.attach(self.wBuffer.buffer, 0, 0);
        self.surface.commit();
    }
};

fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, configured: *bool) void {
    switch (event) {
        .configure => |configure| {
            layer_surface.ackConfigure(configure.serial);
            configured.* = true;
        },
        else => {},
    }
}
