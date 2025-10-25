const std = @import("std");

const ft = @import("./context.zig").ft;
const hb = @import("./context.zig").hb;

const Context = @import("./context.zig").Context;
const Monitor = @import("./window.zig").Monitor;
const Callbacks = @import("./window.zig").Callbacks;
const Text = @import("./text_renderer.zig").Text;
const TextRenderer = @import("./text_renderer.zig").TextRenderer;

pub const Widget = union(enum) {
    label: Label,

    pub fn render(self: *Widget, monitor: *Monitor) void {
        switch (self.*) {
            .label => |*l| l.render(monitor),
        }
    }

    pub fn callbacks(self: *Widget) *Callbacks {
        switch (self.*) {
            .label => |*l| return &l.callbacks,
        }
    }
};

pub const Label = struct {
    text: Text,
    tr: TextRenderer,
    alignment: u32,
    callbacks: Callbacks,
    context: *Context,

    pub fn new(text: []const u8, font_size: u32, padding: u32, fg: u32, bg: u32, alignment: u32, context: *Context) anyerror!Label {
        const label_text = TextRenderer.newText(text, font_size, padding, fg, bg, context) catch |err| return err;

        const callbacks = Callbacks {
            .mouseenter = null,
            .mouseleave = null,
            .mousemotion = null,
            .leftpress = null,
            .leftrelease = null,
            .key = null,
        };

        return Label {
            .text = label_text,
            .tr = TextRenderer{},
            .alignment = alignment,
            .callbacks = callbacks,
            .context = context,
        };
    }

    pub fn render(self: *Label, monitor: *Monitor) void {
        self.tr.renderText(self.text, self.alignment, monitor, self.context);
    }

    pub fn deinit(self: *Label) void {
        self.text.deinit(self.context.allocator);
    }
};
