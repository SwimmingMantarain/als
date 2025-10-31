const std = @import("std");

const ctx = @import("./context.zig");
const Context = ctx.Context;
const ft = ctx.ft;
const hb = ctx.hb;

const Buffer = @import("./window.zig").Buffer;

pub const Text = struct {
    glyph_count: u32,
    total_width: i64,
    total_height: i64,
    padding: u32,
    infos: [*]hb.hb_glyph_info_t,
    pos: [*]hb.hb_glyph_position_t,
    bg_w: u32,
    bg_h: u32,
    bg: u32,
    fg: u32,

    pub fn deinit(self: *Text, gpa: *std.mem.Allocator) void {
        gpa.free(self.infos[0..self.glyph_count]);
        gpa.free(self.pos[0..self.glyph_count]);
    }
};

pub const TextRenderer = struct {
    pub fn newText(text: []const u8, font_size: u32, padding: u32, fg: u32, bg: u32, context: *Context) anyerror!Text {
        if (ft.FT_Set_Pixel_Sizes(context.render.ft_face, @intCast(font_size), @intCast(font_size)) != 0) {
            std.debug.print("Failed to set character size\n", .{});
            return error.FailedToSetCharSize;
        }

        const hb_font: *hb.hb_font_t = hb.hb_ft_font_create(context.render.ft_face, null) orelse {
            std.debug.print("Failed to create HarfBuzz font\n", .{});
            return error.FailedToCreateHBFont;
        };
        const hb_buffer: *hb.hb_buffer_t = hb.hb_buffer_create() orelse {
            std.debug.print("Failed to create HarfBuzz buffer\n", .{});
            return error.FailedToCreateHBBuffer;
        };
        defer hb.hb_buffer_destroy(hb_buffer);
        defer hb.hb_font_destroy(hb_font);

        hb.hb_buffer_add_utf8(hb_buffer, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(hb_buffer);

        hb.hb_shape(hb_font, hb_buffer, null, 0);

        var glyph_count: u32 = 0;
        const glyph_info: [*]hb.hb_glyph_info_t = @ptrCast(hb.hb_buffer_get_glyph_infos(hb_buffer, &glyph_count));
        const glyph_pos: [*]hb.hb_glyph_position_t = @ptrCast(hb.hb_buffer_get_glyph_positions(hb_buffer, &glyph_count));

        var total_width: i64 = 0;
        for (0..glyph_count) |i| {
            total_width += @divTrunc(glyph_pos[i].x_advance, 64);
        }

        const face_size = context.render.ft_face.*.size.*.metrics;
        const ascender: i64 = @divTrunc(face_size.ascender, 64);
        const descender: i64 = @divTrunc(face_size.descender, 64);
        const total_height: i64 = ascender - descender; // descender is negative

        const bg_width: u32 = @as(u32, @intCast(total_width)) + 2 * padding;
        const bg_height: u32 = @as(u32, @intCast(total_height)) + 2 * padding;

        const infos = try context.gpa.alloc(hb.hb_glyph_info_t, glyph_count);
        const positions = try context.gpa.alloc(hb.hb_glyph_position_t, glyph_count);

        @memcpy(infos, glyph_info[0..glyph_count]);
        @memcpy(positions, glyph_pos[0..glyph_count]);

        return Text{
            .glyph_count = glyph_count,
            .total_width = total_width,
            .total_height = total_height,
            .padding = padding,
            .infos = infos.ptr,
            .pos = positions.ptr,
            .bg_w = bg_width,
            .bg_h = bg_height,
            .bg = bg,
            .fg = fg,
        };
    }

    pub fn boundingBox(_: *TextRenderer, text: Text, buffer: *Buffer) [2]i64 {
        const bg_x: i64 = @divTrunc(@as(i64, @intCast(buffer.width)) - @as(i64, @intCast(text.bg_w)), 2);
        const bg_y: i64 = @divTrunc(@as(i64, @intCast(buffer.height)) - @as(i64, @intCast(text.bg_h)), 2);

        return .{bg_x, bg_y} ;
    }

    pub fn renderText(self: *TextRenderer, text: Text, alignment: u32, buffer: *Buffer, context: *Context) void {
        const bg_x: i64 = @divTrunc(@as(i64, @intCast(buffer.width)) - @as(i64, @intCast(text.bg_w)), 2);
        const bg_y: i64 = @divTrunc(@as(i64, @intCast(buffer.height)) - @as(i64, @intCast(text.bg_h)), 2);

        // Draw background
        var y: u32 = 0;
        while (y < text.bg_h) : (y += 1) {
            var x: u32 = 0;
            while (x < text.bg_w) : (x += 1) {
                const px = bg_x + @as(i64, @intCast(x));
                const py = bg_y + @as(i64, @intCast(y));

                if (px >= 0 and py >= 0 and 
                    px < @as(i64, @intCast(buffer.width)) and 
                    py < @as(i64, @intCast(buffer.height))) {
                    const idx = @as(usize, @intCast(py)) * buffer.width + @as(usize, @intCast(px));
                    buffer.pixels[idx] = text.bg;
                }
            }
        }

        var text_start_x: i64 = bg_x + @as(i64, @intCast(text.padding));
        const text_start_y: i64 = bg_y + @as(i64, @intCast(text.padding));

        const available_width: i64 = @as(i64, @intCast(text.total_width));
        if (alignment == 0) { // CENTER
            text_start_x += @divTrunc(available_width - text.total_width, 2);
        } else if (alignment == 4) { // RIGHT
            text_start_x += available_width - text.total_width;
        }

        const face_size = context.render.ft_face.*.size.*.metrics;
        const ascender: i64 = @divTrunc(face_size.ascender, 64);

        var pen_x: i64 = text_start_x;
        var pen_y: i64 = text_start_y + ascender;

        // Render each glyph
        for (0..text.glyph_count) |i| {
            const glyph_index = text.infos[i].codepoint;

            if (ft.FT_Load_Glyph(context.render.ft_face, glyph_index, ft.FT_LOAD_RENDER) != 0) {
                std.debug.print("Failed to load glyph {} (glyph_index: {})\n", .{i, glyph_index});
                continue;
            }

            const bitmap: *ft.FT_Bitmap = &context.render.ft_face.*.glyph.*.bitmap;
            const glyph_left = context.render.ft_face.*.glyph.*.bitmap_left;
            const glyph_top = context.render.ft_face.*.glyph.*.bitmap_top;

            const draw_x = pen_x + @as(i64, @intCast(glyph_left)) + @divTrunc(text.pos[i].x_offset, 64);
            const draw_y = pen_y - @as(i64, @intCast(glyph_top)) + @divTrunc(text.pos[i].y_offset, 64);

            self.drawBitmap(bitmap, draw_x, draw_y, text.fg, buffer.pixels, buffer.width, buffer.height);

            pen_x += @divTrunc(text.pos[i].x_advance, 64);
            pen_y += @divTrunc(text.pos[i].y_advance, 64);
        }

    }

    fn drawBitmap(
        _: *TextRenderer,
        bitmap: *ft.FT_Bitmap,
        x: i64,
        y: i64,
        fg: u32,
        pixels: [*]u32,
        parent_width: u64,
        parent_height: u64,
    ) void {
        var row: u32 = 0;
        while (row < bitmap.rows) : (row += 1) {
            var col: u32 = 0;
            while (col < bitmap.width) : (col += 1) {
                const px = x + @as(i64, @intCast(col));
                const py = y + @as(i64, @intCast(row));

                if (px < 0 or py < 0 or 
                    px >= @as(i64, @intCast(parent_width)) or 
                    py >= @as(i64, @intCast(parent_height))) continue;

                const alpha = bitmap.buffer[row * @as(u32, @intCast(bitmap.pitch)) + col];
                if (alpha == 0) continue;

                const pixel_index = @as(usize, @intCast(py)) * parent_width + @as(usize, @intCast(px));

                const text_color: u32 = fg;
                const bg_color = pixels[pixel_index];

                pixels[pixel_index] = blendColor(bg_color, text_color, alpha);
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
