const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const getContext = @import("./bindings.zig").getContext;
const Window = @import("../window.zig").Window;

pub fn luaCreateWindow(L: *Lua) i32 {
    const width = L.toInteger(1) catch 100;
    const height = L.toInteger(2) catch 100;
    const bgcol = L.toInteger(3) catch 0xFF000000;
    const onAllMonitors = L.toBoolean(4);

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const outputs = if (onAllMonitors)
        context.outputs.items
    else
        context.outputs.items[0..1];

    const w = Window.init(
        "als-window",
        @intCast(width), @intCast(height),
        @intCast(bgcol),
        context,
        outputs,
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

    const window_ptr = &context.windows.items[context.windows.items.len - 1];
    const userdata_ptr = L.newUserdata(*Window, 0);
    userdata_ptr.* = window_ptr;

    _ = L.getMetatableRegistry("Window");
    L.setMetatable(-2);

    return 1;
}
