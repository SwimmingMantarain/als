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
    context: *Context,
    width: i32 = 0,
    height: i32 = 0,
    scale: i32 = 1,
    name: []u8 = &[_]u8{},
    ready: bool = false,
};

pub const Monitor = struct {
    output: OutputInfo,
    context: *Context,
    id: u32,
    windows: std.ArrayList(*Window),

    pub fn new(output: OutputInfo, id: u32, context: *Context) anyerror!Monitor {
        const monitor = Monitor{
            .output = output,
            .context = context,
            .id = id,
            .windows = try std.ArrayList(*Window).initCapacity(context.gpa, 5),
        };

        return monitor;
    }

    pub fn deinit(self: *Monitor) void {
        for (self.windows.items) |window| {
            window.deinit(self.context.gpa);
            self.context.gpa.destroy(window);
        }
        self.windows.deinit(self.context.gpa);
    }

    pub fn update(self: *Monitor, display: *wl.Display) anyerror!void {
        if (display.flush() != .SUCCESS) return error.FlushFailed;
        for (self.windows.items) |window| {
            try window.update();
        }
    }

    pub fn new_window(self: *Monitor, w: i64, h: i64, id: u32) anyerror!*Window {
        const widgets = try std.ArrayList(*Widget).initCapacity(self.context.gpa, 10);

        // Check if we want to be as wide or tall as the screen
        const width: u64 = if (w < 0) @as(u64, @intCast(self.output.width)) else @as(u64, @intCast(w));
        const height: u64 = if (h < 0) @as(u64, @intCast(self.output.height)) else @as(u64, @intCast(h));

        const mbuffer = blk: {
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

            const pool = try self.context.wayland.shm.?.createPool(fd, @as(i32, @intCast(size)));
            defer pool.destroy();

            const buffer = try pool.createBuffer(0, @as(i32, @intCast(width)), @as(i32, @intCast(height)), @as(i32, @intCast(stride)), wl.Shm.Format.argb8888);

            break :blk Buffer{
                .buffer = buffer,
                .width = width,
                .height = height,
                .pixels = pixels,
                .pixel_count = pixel_count,
            };
        };

        const surface = try self.context.wayland.compositor.?.createSurface();

        surface.setBufferScale(self.output.scale);

        const region = try self.context.wayland.compositor.?.createRegion();
        region.add(0, 0, @intCast(width), @intCast(height));
        surface.setInputRegion(region);
        region.destroy();

        const layer_surface = try self.context.wayland.layer_shell.?.getLayerSurface(surface, self.output.output, zwlr.LayerShellV1.Layer.overlay, "cat");
        const logical_width = @divTrunc(self.output.width, self.output.scale);
        const logical_height = @divTrunc(self.output.height, self.output.scale);

        layer_surface.setSize(@intCast(logical_width), @intCast(logical_height));
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
            if (self.context.wayland.display.dispatch() != .SUCCESS) return error.DisplayDispatchFailed;
        }

        surface.attach(mbuffer.buffer, 0, 0);
        surface.commit();

        const win_ptr = try self.context.gpa.create(Window);
        win_ptr.* = Window{
            .surface = surface,
            .layer_surface = layer_surface,
            .buffer = mbuffer,
            .bg_color = 0xFF000000,
            .widgets = widgets,
            .active_widget = null,
            .callbacks = callbacks.CallbackHandler.init(self.context.gpa, self.context.lua),
            .context = self.context,
            .id = id,
            .dirty = true,
        };

        errdefer {
            win_ptr.deinit(self.context.gpa);
            self.context.gpa.destroy(win_ptr);
        }

        try self.windows.append(self.context.gpa, win_ptr);

        return win_ptr;
    }

    pub fn get_window(self: *Monitor, id: u32) ?*Window {
        for (self.windows.items) |w| {
            if (w.id == id) return w;
        }

        return null;
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
    active_widget: ?*Widget,
    bg_color: u32,
    callbacks: callbacks.CallbackHandler,
    context: *Context,
    id: u32,
    dirty: bool,

    pub fn deinit(self: *Window, gpa: Allocator) void {
        self.callbacks.deinit();

        const size = self.buffer.width * self.buffer.height * 4;
        posix.munmap(@as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(self.buffer.pixels)))[0..size]);
        self.layer_surface.destroy();
        self.surface.destroy();
        self.buffer.buffer.destroy();

        self.widgets.deinit(gpa);
    }

    pub fn set_pixel(self: *Window, x: u32, y: u32) void {
        self.buffer.pixels[@as(usize, @intCast(y)) * self.buffer.width + @as(usize, @intCast(x))] = 0xFFFFFFFF; // ARGB White
        self.surface.attach(self.buffer.buffer, 0, 0);
        self.surface.commit();
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

    pub fn mouseEnterWidget(self: *Window, x: f64, y: f64) ?*Widget {
        for (self.widgets.items) |widget| {
            if (widget.contains(x, y, &self.buffer) and self.active_widget == null) {
                self.active_widget = widget;
                return widget;
            } 
        }

        return null;
    }

    pub fn mouseLeaveWidget(self: *Window, x: f64, y: f64) ?*Widget {
        for (self.widgets.items) |widget| {
            if (!widget.contains(x, y, &self.buffer) and self.active_widget == widget) {
                self.active_widget = null;
                return widget;
            }
        }

        return null;
    }

    pub fn newLabel(self: *Window, text: []const u8, font_size: u32) anyerror!*Widget {
        const label = Label.new(
            text,
            font_size,
            0xFFFFFFFF, // foreground
            0xFF119911, // background
            0, // Default CENTER
            self.context,
        ) catch |err| return err;

        const label_ptr = try self.context.gpa.create(Widget);
        label_ptr.* = label;

        try self.widgets.append(self.context.gpa, label_ptr);

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
