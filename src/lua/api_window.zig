const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const window = @import("../wayland/window.zig");
const widgets = @import("../widgets/widgets.zig");
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
    id: u32,
    context: *Context,

    pub fn toEdge(self: *luaWindow, edge: i32) void {
        var wins = self.context.monitors.get_windows(self.id, self.context) catch {
            std.debug.print("Unknown window id: {}!\n", .{self.id});
            return;
        };

        defer wins.deinit(self.context.gpa);

        for (wins.items) |w| {
            w.toEdge(edge);
        }
    }

    pub fn newLabel(self: *luaWindow, text: []const u8, font_size: u32) anyerror!luaWidget {
        var wins = try self.context.monitors.get_windows(self.id, self.context);
        defer wins.deinit(self.context.gpa);
        var labels = try std.ArrayList(*widgets.Widget).initCapacity(self.context.gpa, wins.items.len);

        for (wins.items) |w| {
            const label = try w.newLabel(text, font_size);
            try labels.append(self.context.gpa, label);
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

    const lwid = lwin_ptr.newLabel(
        text,
        @intCast(font_size),
    ) catch {
        L.raiseErrorStr("Failed to create label", .{});
        return 0;
    };

    const lwid_ptr = context.gpa.create(luaWidget) catch {
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
