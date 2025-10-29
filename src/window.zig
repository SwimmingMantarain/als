const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Context = @import("./context.zig").Context;
const ft = @import("./context.zig").ft;
const hb = @import("./context.zig").hb;

const Label = @import("./widgets.zig").Label;
const Widget = @import("./widgets.zig").Widget;
const callbacks = @import("./callbacks.zig");

pub const OutputInfo = struct {
    output: *wl.Output,
    width: i32 = 0,
    height: i32 = 0,
    name: []u8 = &[_]u8{},
    allocator: std.mem.Allocator,
    ready: bool = false,
};

pub const Monitor = struct {
    output: OutputInfo,
    context: *Context,
    windows: std.ArrayList(*Window),

    pub fn new(output: OutputInfo, context: *Context) anyerror!Monitor {
        const monitor = Monitor{
            .output = output,
            .context = context,
            .windows = try std.ArrayList(*Window).initCapacity(context.allocator, 5),
        };

        return monitor;
    }

    pub fn deinit(self: *Monitor) void {
        self.windows.deinit(self.context.allocator);
    }

    pub fn update(self: *Monitor, display: *wl.Display) anyerror!void {
        if (display.flush() != .SUCCESS) return error.FlushFailed;
        for (self.windows.items) |window| {
            try window.update();
        }
    }

    pub fn new_window(self: *Monitor, window_name: []const u8, bg_color: u32, w: i64, h: i64) ?*Window {
        const widgets = std.ArrayList(*Widget).initCapacity(self.context.allocator, 10) catch return null;

        // Check if we want to be as wide or tall as the screen
        const width: u64 = if (w < 0) @as(u64, @intCast(self.output.width)) else @as(u64, @intCast(w));
        const height: u64 = if (h < 0) @as(u64, @intCast(self.output.height)) else @as(u64, @intCast(h));

        const mbuffer = blk: {
            const stride = width * 4;
            const size = stride * height;

            const fd = posix.memfd_create(window_name, 0) catch return null;
            posix.ftruncate(fd, size) catch return null;

            const data = posix.mmap(
                null,
                size,
                posix.PROT.READ | posix.PROT.WRITE,
                .{ .TYPE = .SHARED },
                fd,
                0,
            ) catch return null;

            const pixels: [*]u32 = @ptrCast(@alignCast(data.ptr));
            const pixel_count = size / 4;
            @memset(pixels[0..pixel_count], bg_color); // ARGB

            const pool = self.context.shm.?.createPool(fd, @as(i32, @intCast(size))) catch return null;
            defer pool.destroy();

            const buffer = pool.createBuffer(0, @as(i32, @intCast(width)), @as(i32, @intCast(height)), @as(i32, @intCast(stride)), wl.Shm.Format.argb8888) catch return null;

            break :blk Buffer{
                .buffer = buffer,
                .width = width,
                .height = height,
                .pixels = pixels,
                .pixel_count = pixel_count,
            };
        };

        const surface = self.context.compositor.?.createSurface() catch return null;

        const region = self.context.compositor.?.createRegion() catch return null;
        region.add(0, 0, @intCast(width), @intCast(height));
        surface.setInputRegion(region);
        region.destroy();

        const layer_surface = self.context.layer_shell.?.getLayerSurface(surface, self.output.output, zwlr.LayerShellV1.Layer.overlay, "cat") catch return null;

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
            if (self.context.display.dispatch() != .SUCCESS) return null;
        }

        surface.attach(mbuffer.buffer, 0, 0);
        surface.commit();

        const win_ptr = self.context.allocator.create(Window) catch return null;
        win_ptr.* = Window{
            .surface = surface,
            .layer_surface = layer_surface,
            .buffer = mbuffer,
            .widgets = widgets,
            .bg_color = bg_color,
            .callbacks = callbacks.CallbackHandler.init(self.context.allocator, self.context.lua),
            .context = self.context,
            .dirty = true,
        };

        self.windows.append(self.context.allocator, win_ptr) catch return null;

        return win_ptr;
    }
};

pub const Buffer = struct {
    buffer: *wl.Buffer,
    width: u64,
    height: u64,
    pixels: [*]u32,
    pixel_count: usize,
};

pub const Window = struct {
    surface: *wl.Surface,
    layer_surface: *zwlr.LayerSurfaceV1,
    buffer: Buffer,
    widgets: std.ArrayList(*Widget),
    bg_color: u32,
    callbacks: callbacks.CallbackHandler,
    context: *Context,
    dirty: bool,

    pub fn deinit(self: *Window, allocator: *Allocator) void {
        self.callbacks.deinit();

        const size = self.buffer.width * self.buffer.height * 4;
        posix.munmap(@as([*]align(mem.page_size) u8, @ptrCast(self.buffer.pixels))[0..size]);
        self.layer_surface.destroy();
        self.surface.destroy();
        self.buffer.buffer.destroy();

        self.widgets.deinit(allocator);
    }

    pub fn update(self: *Window) anyerror!void {
        if (self.dirty) {
            self.dirty = false;
            self.clear();
        }

        for (self.widgets.items) |widget| {
            widget.render(&self.buffer);
        }

        self.surface.attach(self.buffer.buffer, 0, 0);
        self.surface.commit();
    }

    pub fn hit(self: *Window, x: f64, y: f64) ?*Widget {
        for (self.widgets.items) |widget| {
            if (widget.contains(x, y, &self.buffer)) return widget;
        }
        return null;
    }

    pub fn newLabel(self: *Window, text: []const u8, font_size: u32, padding: u32, alignment: u32) anyerror!*Widget {
        const label = Label.new(
            text,
            font_size,
            padding,
            0xFFFFFFFF, // foreground
            0xFF119911, // background
            alignment,
            self.context,
        ) catch |err| return err;

        const label_ptr = try self.context.allocator.create(Widget);
        label_ptr.* = label;

        try self.widgets.append(self.context.allocator, label_ptr);

        return label_ptr;
    }

    pub fn toEdge(self: *Window, edge: i32) void {
        self.layer_surface.setAnchor(.{
            .bottom = if (edge == 2 or edge == 0) true else false,
            .left = if (edge == 3 or edge == 0) true else false,
            .right = if (edge == 4 or edge == 0) true else false,
            .top = if (edge == 1 or edge == 0) true else false,
        });

        self.surface.commit();
    }

    pub fn clear(self: *Window) void {
        const pixels = self.buffer.pixels;
        const pixel_count = self.buffer.pixel_count;
        @memset(pixels[0..pixel_count], self.bg_color);
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
