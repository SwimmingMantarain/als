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

    L.setField(-2, "__index");

    L.pop(1);
}

