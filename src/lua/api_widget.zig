const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const window = @import("../window.zig");
const widgets = @import("../widgets.zig");
const luaSetWidgetCallback = @import("./callbacks.zig").luaSetWidgetCallback;

pub fn createWidgetMetatable(L: *Lua) void {
    L.newMetatable("Widget") catch return;

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaSetWidgetCallback));
    L.setField(-2, "set_callback");

    L.pushFunction(zlua.wrap(luaSetWidgetBg));
    L.setField(-2, "set_bg");

    L.pushFunction(zlua.wrap(luaSetWidgetFg));
    L.setField(-2, "set_fg");

    L.pushFunction(zlua.wrap(luaSetWidgetText));
    L.setField(-2, "set_text");

    L.pushFunction(zlua.wrap(luaSetWidgetEdge));
    L.setField(-2, "to_edge");

    L.setField(-2, "__index");

    L.pop(1);
}

pub const luaWidget = struct {
    widgets: std.ArrayList(*widgets.Widget),

    pub fn setBg(self: *luaWidget, color: u32) void {
        for (self.widgets.items) |widget| {
            switch (widget.*) {
                .label => {
                    widget.label.text.bg = color;
                },
            }
        }
    }

    pub fn setFg(self: *luaWidget, color: u32) void {
        for (self.widgets.items) |widget| {
            switch (widget.*) {
                .label => {
                    widget.label.text.fg = color;
                }
            }
        }
    }

    pub fn setText(self: *luaWidget, text: []const u8) void {
        for (self.widgets.items) |widget| {
            switch (widget.*) {
                .label => {
                    widget.label.set_text(text);
                }
            }
        }
    }

    pub fn setEdge(self: *luaWidget, edge: u32) void {
        for (self.widgets.items) |widget| {
            switch (widget.*) {
                .label => {
                    widget.label.set_edge(edge);
                }
            }
        }
    }
};

fn luaSetWidgetEdge(L: *Lua) i32 {
    const lwid_ptr = L.checkUserdata(*luaWidget, 1, "Widget").*;

    const edge = L.toInteger(2) catch 0; // default CENTER

    lwid_ptr.setEdge(@intCast(edge));

    return 0;
}

fn luaSetWidgetBg(L: *Lua) i32 {
    const lwid_ptr_ptr = L.checkUserdata(*luaWidget, 1, "Widget");
    const lwid_ptr = lwid_ptr_ptr.*;

    const color = L.toInteger(2) catch 0xFF000000; // argb black

    lwid_ptr.setBg(@intCast(color));

    return 0;
}

fn luaSetWidgetFg(L: *Lua) i32 {
    const lwid_ptr_ptr = L.checkUserdata(*luaWidget, 1, "Widget");
    const lwid_ptr = lwid_ptr_ptr.*;

    const color = L.toInteger(2) catch 0xFFFFFFFF; // argb white

    lwid_ptr.setFg(@intCast(color));

    return 0;
}

fn luaSetWidgetText(L: *Lua) i32 {
    const lwid_ptr_ptr = L.checkUserdata(*luaWidget, 1, "Widget");
    const lwid_ptr = lwid_ptr_ptr.*;

    const text = L.toString(2) catch "error";

    lwid_ptr.setText(text);

    return 0;
}
