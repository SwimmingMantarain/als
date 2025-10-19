const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const Context = @import("./context.zig").Context;
const window = @import("./window.zig");

pub fn init(L: *Lua, context: *Context) void {
    L.pushLightUserdata(context);
    L.setField(zlua.registry_index, "context");

    registerModule(L);
}

fn registerModule(L: *Lua) void {
    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaCreateWindow));
    L.setField(-2, "create_window");

    L.setGlobal("als");
}

fn getContext(L: *Lua) anyerror!*Context {
    _ = L.getField(zlua.registry_index, "context");
    const context = try L.toUserdata(*Context, -1);
    L.pop(1);
    return @ptrCast(@alignCast(context));
}

fn luaCreateWindow(L: *Lua) i32 {
    const width = L.toInteger(1) catch 100;
    const height = L.toInteger(2) catch 100;
    const x = L.toInteger(3) catch 0;
    const y = L.toInteger(4) catch 0;

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const w = window.Window.init(
        "als-window",
        @intCast(width), @intCast(height),
        @intCast(x), @intCast(y),
        context.display,
        context.compositor.?,
        context.shm.?,
        context.layer_shell.?,
        context.outputs.items[0].output
    ) catch {
        _ = L.pushString("Failed to create window");
        L.raiseError();
        return 0;
    };

    context.windows.append(context.allocator, w) catch {
        _ = L.pushString("Failed to append window");
        L.raiseError();
        return 0;
    };

    L.pushInteger(@intCast(context.windows.items.len - 1));
    return 1;
}
