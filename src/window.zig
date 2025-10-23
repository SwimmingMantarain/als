const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Context = @import("./context.zig").Context;
const ft = @import("./context.zig").ft;
const hb = @import("./context.zig").hb;

const Label = @import("./widgets.zig").Label;
const WidgetBuffer = @import("./widgets.zig").WidgetBuffer;

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
    width: u64,
    height: u64,
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
    bg_color: u32,
    widgets: std.Arraylist(Label)
    callbacks: Callbacks,
    context: *Context,

    pub fn init(
        window_name: []const u8,
        w: i64,
        h: i64,
        bg_color: u32,
        context: *Context,
        outputs: []OutputInfo,
    ) !Window {
        var monitors =  try std.ArrayList(Monitor).initCapacity(context.allocator, 5);
        var widgets = try std.ArrayList(Label).initCapacity(context.allocator, 10);

        for (outputs) |out_info| {
            // Check if we want to be as wide or tall as the screen
            const width: u64 = if (w < 0) @as(u64, @intCast(out_info.width)) else @as(u64, @intCast(w));
            const height: u64 = if (h < 0) @as(u64, @intCast(out_info.height)) else @as(u64, @intCast(h));

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
                @memset(pixels[0..pixel_count], bg_color); // ARGB

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
                    .width = width,
                    .height = height,
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
            layer_surface.setExclusiveZone(@intCast(height));
            layer_surface.setAnchor(.{
                .bottom = true,
                .left = true,
                .right = true,
                .top = true,
            });

            layer_surface.setKeyboardInteractivity(.on_demand);

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
            .bg_color = bg_color,
            .widgets = widgets,
            .callbacks = callbacks,
            .context = context,
        };
    }

    pub fn deinit(self: *Window) void {
        for (self.monitors.items) |*monitor| {
            monitor.layer_surface.destroy();
            monitor.surface.destroy();
            monitor.buffer.buffer.destroy();
        }
    }

    pub fn update(self: *Window, display: *wl.Display, context: *Context) anyerror!void {
        if (display.flush() != .SUCCESS) return error.FlushFailed;

        self.clear();

        for (self.monitors.items) |*monitor| {
            for (self.widgets.items) |*widget| {
                widget.render(monitor.buffer.pixels, context);
            }
            monitor.surface.commit();
        }
    }

    pub fn newLabel(self: *Window, text: []const u8, font_size: u32, width: u32, height: u32, padding: u32, alignment: u32, context: *Context) anyerror!*Label {
        const wb = WidgetBuffer{
            .width = width + padding * 2,
            .height = height + padding * 2,
            .stride = self.width,
            .offset_x = self.width / 2 - width / 2 - padding,
            .offset_y = self.height / 2 - height / 2 - paddding,
        };

        const label = Label{
            .wb = wb,
            .text = text,
            .font_size = font_size,
            .alignment = alignment,
            .bg_color = 0xFF111111,
            .fg_color = 0xFFFFFFFF,
        };

        try self.widgets.append(context.allocator, label);

        return &self.widget.items[self.widget.items.len - 1];
    }

    pub fn toEdge(self: *Window, edge: i32) void {
        for (self.monitors.items) |*monitor| {
            monitor.layer_surface.setAnchor(.{
                .bottom = if (edge == 2 or edge == 0) true else false,
                .left = if (edge == 3 or edge == 0) true else false,
                .right = if (edge == 4 or edge == 0) true else false,
                .top = if (edge == 1 or edge == 0) true else false,
            });

            monitor.surface.commit();
        }
    }

    pub fn clear(self: *Window) void {
        for (self.monitors.items) |*monitor| {
            if (monitor == self.context.active_monitor) {
                const pixels = monitor.buffer.pixels;
                const pixel_count = monitor.buffer.pixel_count;
                @memset(pixels[0..pixel_count], self.bg_color);
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
