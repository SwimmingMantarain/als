const ft = @import("./context.zig").ft;
const hb = @import("./context.zig").hb;


pub const WidgetBuffer = struct {
    width: u32,
    height: u32,
    stride: u32, // parent buffer width
    offset_x: u32,
    offset_y: u32,

    pub fn setPixel(self: *WidgetBuffer, x: u64, y: u64, color: u32, pixels: [*]u32) void {
        const abs_x = x + self.offset_x;
        const abs_y = y + self.offset_y;

        if (abs_x < self.width and abs_y < self.height) {
            const idx = @as(usize, @intCast(abs_y)) * self.stride + @as(usize, @intCast(abs_x));
            pixels[idx] = color; // ARGB
        }
    }
}

pub const Label = struct {
    wb: WidgetBuffer,
    text: []const u8,
    font_size: u32,
    alignment: u32,
    bg_color: u32,
    fg_color: u32,

    pub const render(self: *Label, pixels: [*]u32, context: *Context) void {
        if (ft.FT_Set_Pixel_Sizes(context.ft_face, @intCast(self.font_size), @intCast(self.font_size)) != 0) {
            std.debug.print("Failed to set character size\n", .{});
            return;
        }

        const hb_font: *hb.hb_font_t = hb.hb_ft_font_create(context.ft_face, null).?;
        const hb_buffer: *hb.hb_buffer_t = hb.hb_buffer_create().?;

        hb.hb_buffer_add_utf8(hb_buffer, self.text.ptr, @intCast(self.text.len), 0, @intCast(self.text.len));
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
};
