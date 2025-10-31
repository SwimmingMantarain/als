const std = @import("std");

const ft = @import("./context.zig").ft;
const hb = @import("./context.zig").hb;

const Context = @import("./context.zig").Context;
const Buffer = @import("./window.zig").Buffer;
const callbacks = @import("./callbacks.zig");
const Text = @import("./text_renderer.zig").Text;
const TextRenderer = @import("./text_renderer.zig").TextRenderer;

pub const Widget = union(enum) {
    label: Label,

    pub fn render(self: *Widget, buffer: *Buffer) void {
        switch (self.*) {
            .label => |*l| l.render(buffer),
        }
    }

    pub fn contains(self: *Widget, x: f64, y: f64, buffer: *Buffer) bool {
        switch (self.*) {
            .label => |*l| {
                return l.contains(x, y, buffer);
            },
        }
    }
};

pub const Label = struct {
    text: Text,
    tr: TextRenderer,
    alignment: u32,
    callbacks: callbacks.CallbackHandler,
    font_size: u32,
    padding: u32,
    context: *Context,

    pub fn new(text: []const u8, font_size: u32, padding: u32, fg: u32, bg: u32, alignment: u32, context: *Context) anyerror!Widget{
        const label_text = TextRenderer.newText(text, font_size, padding, fg, bg, context) catch |err| return err;
        const label = Label {
            .text = label_text,
            .tr = TextRenderer{},
            .alignment = alignment,
            .callbacks = callbacks.CallbackHandler.init(context.gpa, context.lua),
            .font_size = font_size,
            .padding = padding,
            .context = context,
        };

        return Widget { .label = label };
    }

    pub fn contains(self: *Label, x: f64, y: f64, buffer: *Buffer) bool {
        const bbox = self.tr.boundingBox(self.text, buffer);
        const bbx = @as(f64, @floatFromInt(bbox[0]));
        const bby = @as(f64, @floatFromInt(bbox[1]));

        return (x > bbx and
                x < bbx + @as(f64, @floatFromInt(self.text.bg_w)) and
                y > bby and
                y < bby + @as(f64, @floatFromInt(self.text.bg_h)));
    }

    pub fn set_text(self: *Label, text: []const u8) void {
        const label_text = TextRenderer.newText(text, self.font_size, self.padding, self.text.fg, self.text.bg, self.context) catch return;

        self.text = label_text;
    }

    pub fn render(self: *Label, buffer: *Buffer) void {
        self.tr.renderText(self.text, self.alignment, buffer, self.context);
    }

    pub fn deinit(self: *Label) void {
        self.callbacks.deinit();
        self.text.deinit(self.context.gpa);
    }
};
