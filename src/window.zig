const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Context = @import("./context.zig").Context;

pub const OutputInfo = struct {
    output: *wl.Output,
    width: i32 = 0,
    height: i32 = 0,
    ready: bool = false,
};

pub const Monitor = struct {
    surface: *wl.Surface,
    layer_surface: *zwlr.LayerSurfaceV1,
    buffer: Buffer,
};

const Buffer = struct {
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
    monitors: std.ArrayList(Monitor),
    callbacks: Callbacks,
    context: *Context,
    x: i32,
    y: i32,
    width: u64,
    height: u64,

    pub fn init(
        window_name: []const u8,
        width: u64,
        height: u64,
        x: i32,
        y: i32,
        context: *Context,
        outputs: []OutputInfo,
    ) !Window {
        var monitors =  try std.ArrayList(Monitor).initCapacity(context.allocator, 5);

        for (outputs) |out_info| {
            const mbuffer = blk: {
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

                const pool = try context.shm.?.createPool(fd, @as(i32, @intCast(size)));
                defer pool.destroy();

                const buffer = try pool.createBuffer(
                    0,
                    @as(i32, @intCast(width)),
                    @as(i32, @intCast(height)),
                    @as(i32, @intCast(stride)),
                    wl.Shm.Format.argb8888
                );

                break :blk Buffer {
                    .buffer = buffer,
                    .pixels = pixels,
                    .pixel_count = pixel_count,
                };
            };

            const surface = try context.compositor.?.createSurface();

            const region = try context.compositor.?.createRegion();
            region.add(0, 0, @intCast(width), @intCast(height));
            surface.setInputRegion(region);
            region.destroy();

            const layer_surface = try context.layer_shell.?.getLayerSurface(
                surface,
                out_info.output,
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
                if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
            }

            surface.attach(mbuffer.buffer, 0, 0);
            surface.commit();

            const mon = Monitor {
                .surface = surface,
                .layer_surface = layer_surface,
                .buffer = mbuffer,
            };

            monitors.append(context.allocator, mon) catch {
                std.debug.print("Failed to append monitor\n", .{});
            };
        }

        const callbacks = Callbacks{
            .leftpress = null,
            .leftrelease = null,
            .mouseenter = null,
            .mouseleave = null,
            .mousemotion = null,
            .key = null,
        };

        return Window{
            .monitors = monitors,
            .callbacks = callbacks,
            .context = context,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Window) void {
        for (self.monitors.items) |*monitor| {
            monitor.layer_surface.destroy();
            monitor.surface.destroy();
            monitor.buffer.buffer.destroy();
        }
    }

    pub fn update(_: *Window, display: *wl.Display) anyerror!void {
        if (display.flush() != .SUCCESS) return error.FlushFailed;
    }

    pub fn setPos(self: *Window, x: i32, y: i32) void {
        for (self.monitors.items) |*monitor| {
            if (monitor == self.context.active_monitor) {
                monitor.layer_surface.setMargin(0, 0, y, x); // top right bottom left
                monitor.surface.commit();
            }
        }
    }

    pub fn setColor(self: *Window, color: u32) void {
        for (self.monitors.items) |*monitor| {
            if (monitor == self.context.active_monitor) {
                const pixels = monitor.buffer.pixels;
                const pixel_count = monitor.buffer.pixel_count;
                @memset(pixels[0..pixel_count], color); // ARGB
                monitor.surface.attach(monitor.buffer.buffer, 0, 0);
                monitor.surface.commit();
            }
        }
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
