const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const getContext = @import("./bindings.zig").getContext;
const Window = @import("../wayland/window.zig").Window;
const luaWindow = @import("./api_window.zig").luaWindow;

pub fn luaCreateWindow(L: *Lua) i32 {
    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const width = L.toInteger(1) catch 100;
    const height = L.toInteger(2) catch 100;
    const monitors = L.toString(3) catch {
        L.raiseErrorStr("Expected string of window name or 'all'", .{});
        return 0;
    };

    if (width <= -2 or height <= -2) { // -1: SCREEN_WDITH, SCREEN_HEIGHT
        L.raiseErrorStr("Width and Height must be bigger than -2", .{});
        return 0;
    }

    const lwin_ptr = context.monitors.new_window(context.gpa, width, height, monitors, context) catch |err| {
        const err_str: []const u8 = @errorName(err);
        L.raiseErrorStr("Error while creating window: %s", .{err_str.ptr});
        return 0;
    };

    const userdata_ptr = L.newUserdata(*luaWindow, 0);
    userdata_ptr.* = lwin_ptr;

    _ = L.getMetatableRegistry("Window");
    L.setMetatable(-2);

    return 1;
}
