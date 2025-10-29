const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const window = @import("../window.zig");
const widgets = @import("../widgets.zig");
const getContext = @import("./bindings.zig").getContext;
const Context = @import("../context.zig").Context;
const luaWidget = @import("./api_widget.zig").luaWidget;
const luaSetWindowCallback = @import("./callbacks.zig").luaSetWindowCallback;

pub fn createWindowMetatable(L: *Lua) void {
    L.newMetatable("Window") catch return;

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaSetWindowCallback));
    L.setField(-2, "set_callback");

    L.pushFunction(zlua.wrap(luaSetWindowEdge));
    L.setField(-2, "to_edge");

    L.pushFunction(zlua.wrap(luaWindowNewLabel));
    L.setField(-2, "new_label");

    L.setField(-2, "__index");

    L.pop(1);
}

pub const luaWindow = struct {
    context: *Context,
    windows: std.ArrayList(*window.Window),

    pub fn toEdge(self: *luaWindow, edge: i32) void {
        for (self.windows.items) |w| {
            w.toEdge(edge);
        }
    }

    pub fn newLabel(self: *luaWindow, text: []const u8, font_size: u32, padding: u32, alignment: u32) anyerror!luaWidget {
        var labels = try std.ArrayList(*widgets.Widget).initCapacity(self.context.allocator, self.windows.items.len);

        for (self.windows.items) |w| {
            const label = try w.newLabel(text, font_size, padding, alignment);
            try labels.append(self.context.allocator, label);
        }

        return luaWidget{
            .widgets = labels,
        };
    }
};

fn luaSetWindowEdge(L: *Lua) i32 {
    const lwin_ptr_ptr = L.checkUserdata(*luaWindow, 1, "Window");
    const lwin_ptr = lwin_ptr_ptr.*;

    const edge = L.toInteger(2) catch 0; // 0 -> center

    lwin_ptr.toEdge(@intCast(edge));

    return 0;
}

fn luaWindowNewLabel(L: *Lua) i32 {
    const lwin_ptr_ptr = L.checkUserdata(*luaWindow, 1, "Window");
    const lwin_ptr = lwin_ptr_ptr.*;

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const text = L.toString(2) catch "label";
    const font_size = L.toInteger(3) catch 16;
    const padding = L.toInteger(4) catch 0;
    const alignment = L.toInteger(5) catch 0; // 0 -> center

    const lwid = lwin_ptr.newLabel(
        text,
        @intCast(font_size),
        @intCast(padding),
        @intCast(alignment),
    ) catch {
        L.raiseErrorStr("Failed to create label", .{});
        return 0;
    };

    const lwid_ptr = context.allocator.create(luaWidget) catch {
        L.raiseErrorStr("Failed to allocate memory for luaLabel", .{});
        return 0;
    };
    lwid_ptr.* = lwid;

    const userdata_ptr = L.newUserdata(*luaWidget, 0);
    userdata_ptr.* = lwid_ptr;

    _ = L.getMetatableRegistry("Widget");
    L.setMetatable(-2);

    return 1;
}
