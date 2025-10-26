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

    pub fn contains(self: *Widget, x: f64, y: f64) bool {
        switch (self.*) {
            .label => |*l| {
                return l.contains(x, y);
            },
        }
    }
};

pub const Label = struct {
    text: Text,
    tr: TextRenderer,
    alignment: u32,
    x: f64,
    y: f64,
    callbacks: callbacks.CallbackHandler,
    context: *Context,

    pub fn new(text: []const u8, font_size: u32, padding: u32, fg: u32, bg: u32, alignment: u32, context: *Context) anyerror!Label {
        const label_text = TextRenderer.newText(text, font_size, padding, fg, bg, context) catch |err| return err;
        return Label {
            .text = label_text,
            .tr = TextRenderer{},
            .alignment = alignment,
            .x = 0, // Will be set after render
            .y = 0,
            .callbacks = callbacks.CallbackHandler.init(context.allocator, context.lua),
            .context = context,
        };
    }

    pub fn contains(self: *Label, x: f64, y: f64) bool {
        return (x > self.x and
                x < self.x + @as(f64, @floatFromInt(self.text.total_width)) and
                y > self.y and
                y < self.y + @as(f64, @floatFromInt(self.text.total_height)));
    }

    pub fn render(self: *Label, monitor: *Monitor) void {
        self.tr.renderText(self.text, self.alignment, monitor, self.context);

        const bbox = self.tr.boundingBox(self.text, monitor);
        self.x = @floatFromInt(bbox[0]);
        self.y = @floatFromInt(bbox[1]);
    }

    pub fn deinit(self: *Label) void {
        self.callbacks.deinit();
        self.text.deinit(self.context.allocator);
    }
};
