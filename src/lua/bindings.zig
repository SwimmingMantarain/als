const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const Context = @import("../context.zig").Context;

const luaCreateWindow = @import("./api_als.zig").luaCreateWindow;

const createWindowMetatable = @import("./api_window.zig").createWindowMetatable;
const createWidgetMetatable = @import("./api_widget.zig").createWidgetMetatable;


pub fn init(L: *Lua, context: *Context) void {
    L.pushLightUserdata(context);
    L.setField(zlua.registry_index, "context");

    registerModule(L);
}

fn registerModule(L: *Lua) void {
    createWindowMetatable(L);
    createWidgetMetatable(L);

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaCreateWindow));
    L.setField(-2, "create_window");

    L.setGlobal("als");

    // Global manim like enum stuff
    L.pushInteger(1);
    L.setGlobal("UP");

    L.pushInteger(2);
    L.setGlobal("DOWN");

    L.pushInteger(3);
    L.setGlobal("LEFT");

    L.pushInteger(4);
    L.setGlobal("RIGHT");

    L.pushInteger(0);
    L.setGlobal("CENTER");

    L.pushInteger(-1);
    L.setGlobal("SCREEN_WIDTH");
    
    L.pushInteger(-1);
    L.setGlobal("SCREEN_HEIGHT");
}

pub fn getContext(L: *Lua) anyerror!*Context {
    _ = L.getField(zlua.registry_index, "context");
    const context = try L.toUserdata(*Context, -1);
    L.pop(1);
    return @ptrCast(@alignCast(context));
}
