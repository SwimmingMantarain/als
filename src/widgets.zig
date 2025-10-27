const std = @import("std");

const ft = @import("./context.zig").ft;
const hb = @import("./context.zig").hb;

const Context = @import("./context.zig").Context;
const Monitor = @import("./window.zig").Monitor;
const callbacks = @import("./callbacks.zig");
const Text = @import("./text_renderer.zig").Text;
const TextRenderer = @import("./text_renderer.zig").TextRenderer;

pub const Widget = union(enum) {
    label: Label,

    pub fn render(self: *Widget, monitor: *Monitor) void {
        switch (self.*) {
            .label => |*l| l.render(monitor),
        }
    }

    pub fn contains(self: *Widget, x: f64, y: f64, monitor: *Monitor) bool {
        switch (self.*) {
            .label => |*l| {
                return l.contains(x, y, monitor);
            },
        }
    }
};

pub const Label = struct {
    text: Text,
    tr: TextRenderer,
    alignment: u32,
    callbacks: callbacks.CallbackHandler,
    context: *Context,

    pub fn new(text: []const u8, font_size: u32, padding: u32, fg: u32, bg: u32, alignment: u32, context: *Context) anyerror!Label {
        const label_text = TextRenderer.newText(text, font_size, padding, fg, bg, context) catch |err| return err;
        return Label {
            .text = label_text,
            .tr = TextRenderer{},
            .alignment = alignment,
            .callbacks = callbacks.CallbackHandler.init(context.allocator, context.lua),
            .context = context,
        };
    }

    pub fn contains(self: *Label, x: f64, y: f64, monitor: *Monitor) bool {
        const bbox = self.tr.boundingBox(self.text, monitor);
        const bbx = @as(f64, @floatFromInt(bbox[0]));
        const bby = @as(f64, @floatFromInt(bbox[1]));

        return (x > bbx and
                x < bbx + @as(f64, @floatFromInt(self.text.bg_w)) and
                y > bby and
                y < bby + @as(f64, @floatFromInt(self.text.bg_h)));
    }

    pub fn render(self: *Label, monitor: *Monitor) void {
        self.tr.renderText(self.text, self.alignment, monitor, self.context);
    }

    pub fn deinit(self: *Label) void {
        self.callbacks.deinit();
        self.text.deinit(self.context.allocator);
    }
};
