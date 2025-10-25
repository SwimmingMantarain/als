const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const window = @import("../window.zig");
const widgets = @import("../widgets.zig");
const getContext = @import("./bindings.zig").getContext;
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

fn luaSetWindowEdge(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const edge = L.toInteger(2) catch 0; // 0 -> center

    window_ptr.toEdge(@intCast(edge));

    return 0;
}

fn luaWindowNewLabel(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const text = L.toString(2) catch "label";
    const font_size = L.toInteger(3) catch 16;
    const padding = L.toInteger(4) catch 0;
    const alignment = L.toInteger(5) catch 0; // 0 -> center

    const label = window_ptr.newLabel(
        text,
        @intCast(font_size),
        @intCast(padding), @intCast(alignment),
        context,
    ) catch {
        L.raiseErrorStr("Failed to create label", .{});
        return 0;
    };

    const widget = widgets.Widget{
        .label = label,
    };

    const w_ptr = context.allocator.create(widgets.Widget) catch {
        L.raiseErrorStr("Failed to allocatoe memory for new Widget", .{});
        return 0;
    };
    w_ptr.* = widget;

    window_ptr.widgets.append(context.allocator, w_ptr) catch {
        L.raiseErrorStr("Failed to append label", .{});
        return 0;
    };

    const userdata_ptr = L.newUserdata(*widgets.Widget, 0);
    userdata_ptr.* = w_ptr;

    _ = L.getMetatableRegistry("Widget");
    L.setMetatable(-2);

    return 1;
}
