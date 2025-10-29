const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const getContext = @import("./bindings.zig").getContext;
const Window = @import("../window.zig").Window;
const luaWindow = @import("./api_window.zig").luaWindow;

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

    const monitors = if (onAllMonitors) context.monitors.items else context.monitors.items[0..1];
    var windows = std.ArrayList(*Window).initCapacity(context.allocator, monitors.len) catch {
        L.raiseErrorStr("Failed to allocate memory for window(s)", .{});
        return 0;
    };

    for (monitors) |monitor| {
        const win_ptr = monitor.new_window("als-window", @intCast(bgcol), @intCast(width), @intCast(height));
        if (win_ptr == null) {
            L.raiseErrorStr("Failed to create window", .{});
            return 0;
        }
        windows.append(context.allocator, win_ptr.?) catch {
            L.raiseErrorStr("Failed to append window", .{});
            return 0;
        };
    }

    const lwin = luaWindow{
        .windows = windows,
        .context = context,
    };

    const lwin_ptr = context.allocator.create(luaWindow) catch {
        L.raiseErrorStr("Failed to allocator memory for luaWindow", .{});
        return 0;
    };

    lwin_ptr.* = lwin;

    const userdata_ptr = L.newUserdata(*luaWindow, 0);
    userdata_ptr.* = lwin_ptr;

    _ = L.getMetatableRegistry("Window");
    L.setMetatable(-2);

    return 1;
}
