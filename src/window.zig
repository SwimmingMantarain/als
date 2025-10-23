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
    callbacks: Callbacks,
    context: *Context,

    pub fn init(
        window_name: []const u8,
        w: i64,
        h: i64,
        context: *Context,
        outputs: []OutputInfo,
    ) !Window {
        var monitors =  try std.ArrayList(Monitor).initCapacity(context.allocator, 5);

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
                @memset(pixels[0..pixel_count], 0xFF000000); // ARGB

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

    pub fn update(_: *Window, display: *wl.Display) anyerror!void {
        if (display.flush() != .SUCCESS) return error.FlushFailed;
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

    pub fn drawText(self: *Window, x: i32, y: i32, text: []const u8, font: []const u8, size: i32, context: *Context) void {
        _ = font;

        if (ft.FT_Set_Pixel_Sizes(context.ft_face, @intCast(size), @intCast(size)) != 0) {
            std.debug.print("Failed to set character size\n", .{});
            return;
        }

        const hb_font: *hb.hb_font_t = hb.hb_ft_font_create(context.ft_face, null).?;
        const hb_buffer: *hb.hb_buffer_t = hb.hb_buffer_create().?;

        hb.hb_buffer_add_utf8(hb_buffer, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(hb_buffer);

        hb.hb_shape(hb_font, hb_buffer, null, 0);

        var glyph_count: u32 = 0;
        const glyph_info: *hb.hb_glyph_info_t = hb.hb_buffer_get_glyph_infos(hb_buffer, &glyph_count);
        const glyph_pos: *hb.hb_glyph_position_t = hb.hb_buffer_get_glyph_positions(hb_buffer, &glyph_count);

        const infos: [*]hb.hb_glyph_info_t = @ptrCast(glyph_info);
        const positions: [*]hb.hb_glyph_position_t = @ptrCast(glyph_pos);

        var pen_x: i32 = x;
        var pen_y: i32 = y;

        for (0..glyph_count) |i| {
            const glyph_index = infos[i].codepoint;

            if (ft.FT_Load_Glyph(context.ft_face, glyph_index, ft.FT_LOAD_RENDER) != 0) {
                continue;
            }

            const bitmap: *ft.FT_Bitmap = &context.ft_face.*.glyph.*.bitmap;
            const glyph_left = context.ft_face.*.glyph.*.bitmap_left;
            const glyph_top = context.ft_face.*.glyph.*.bitmap_top;

            const draw_x = pen_x + @as(i32, @intCast(glyph_left)) + @divTrunc(positions[i].x_offset, 64);
            const draw_y = pen_y - @as(i32, @intCast(glyph_top)) + @divTrunc(positions[i].y_offset, 64);

            self.drawBitmap(bitmap, draw_x, draw_y);

            pen_x += @divTrunc(positions[i].x_advance, 64);
            pen_y += @divTrunc(positions[i].y_advance, 64);
        }

        for (self.monitors.items) |*monitor| {
            monitor.surface.attach(monitor.buffer.buffer, 0, 0);
            monitor.surface.commit();
        }

        // Clean up
        hb.hb_buffer_destroy(hb_buffer);
        hb.hb_font_destroy(hb_font);
    }

    fn drawBitmap(self: *Window, bitmap: *ft.FT_Bitmap, x: i32, y: i32) void {
        for (self.monitors.items) |*monitor| {
            const pixels = monitor.buffer.pixels;

            var row: u32 = 0;
            while (row < bitmap.rows) : (row += 1) {
                var col: u32 = 0;
                while (col < bitmap.width) : (col += 1) {
                    const px = x + @as(i32, @intCast(col));
                    const py = y + @as(i32, @intCast(row));

                    if (px < 0 or py < 0 or px >= monitor.buffer.width or py >= monitor.buffer.height) continue;

                    const alpha = bitmap.buffer[row * @as(u32, @intCast(bitmap.pitch)) + col];
                    if (alpha == 0) continue;

                    const pixel_index = @as(usize, @intCast(py)) * monitor.buffer.width + @as(usize, @intCast(px));

                    const text_color: u32 = 0xFFFFFFFF; // White ARGB
                    const bg_color = pixels[pixel_index];

                    pixels[pixel_index] = blendColor(bg_color, text_color, alpha);
                }
            }
        }
    }

    fn blendColor(bg: u32, fg: u32, alpha: u8) u32 {
        const alpha_f = @as(f32, @floatFromInt(alpha)) / 255.0;

        const bg_a = @as(u8, @intCast((bg >> 24) & 0xFF));
        const bg_r = @as(u8, @intCast((bg >> 16) & 0xFF));
        const bg_g = @as(u8, @intCast((bg >> 8) & 0xFF));
        const bg_b = @as(u8, @intCast(bg & 0xFF));

        const fg_r = @as(u8, @intCast((fg >> 16) & 0xFF));
        const fg_g = @as(u8, @intCast((fg >> 8) & 0xFF));
        const fg_b = @as(u8, @intCast(fg & 0xFF));

        const out_r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(fg_r)) * alpha_f + @as(f32, @floatFromInt(bg_r)) * (1.0 - alpha_f)));
        const out_g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(fg_g)) * alpha_f + @as(f32, @floatFromInt(bg_g)) * (1.0 - alpha_f)));
        const out_b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(fg_b)) * alpha_f + @as(f32, @floatFromInt(bg_b)) * (1.0 - alpha_f)));

        return (@as(u32, bg_a) << 24) | (@as(u32, out_r) << 16) | (@as(u32, out_g) << 8) | @as(u32, out_b);
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
