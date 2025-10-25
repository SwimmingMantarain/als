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
    if (width <= -2 or height <= -2) { // -1: SCREEN_WDITH, SCREEN_HEIGHT
        L.raiseErrorStr("Width and Height must be bigger than -2", .{});
        return 0;
    }

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

    const w_ptr = context.allocator.create(Window) catch {
        L.raiseErrorStr("Failed to allocate memory for new Window", .{});
        return 0;
    };
    w_ptr.* = w;
    context.windows.append(context.allocator, w_ptr) catch {
        _ = L.pushString("Failed to append window");
        L.raiseError();
        return 0;
    };

    const userdata_ptr = L.newUserdata(*Window, 0);
    userdata_ptr.* = w_ptr;

    _ = L.getMetatableRegistry("Window");
    L.setMetatable(-2);

    return 1;
}
