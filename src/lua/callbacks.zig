const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const Context = @import("../context.zig").Context;
const getContext = @import("./api_als.zig").getContext;
const widgets = @import("../widgets.zig");
const window = @import("../window.zig");
const callbacks = @import("../callbacks.zig");

pub fn luaSetWidgetCallback(L: *Lua) i32 {
    const widget_ptr_ptr = L.checkUserdata(*widgets.Widget, 1, "Widget");
    const widget_ptr = widget_ptr_ptr.*;

    const callback_type_str = L.toString(2) catch {
        L.raiseErrorStr("Expected string as 2nd arg", .{});
        return 0;
    };

    if (!L.isFunction(3)) {
        L.raiseErrorStr("Expected func as 3rd arg", .{});
        return 0;
    }

    // Convert string to enum
    const callback_type = std.meta.stringToEnum(callbacks.CallbackType, callback_type_str) orelse {
        L.raiseErrorStr("Unknown callback type", .{});
        return 0;
    };

    L.pushValue(3);
    const ref = L.ref(zlua.registry_index) catch {
        L.raiseErrorStr("Failed to store callback", .{});
        return 0;
    };

    switch (widget_ptr.*) {
        .label => {
            widget_ptr.label.callbacks.set(callback_type, ref) catch {
                L.unref(zlua.registry_index, ref);
                L.raiseErrorStr("Failed to set callback", .{});
                return 0;
            };
        },
    }

    return 0;
}

pub fn luaSetWindowCallback(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const callback_type_str = L.toString(2) catch {
        L.raiseErrorStr("Expected string as 2nd arg", .{});
        return 0;
    };

    if (!L.isFunction(3)) {
        L.raiseErrorStr("Expected func as 3rd arg", .{});
        return 0;
    }

    const callback_type = std.meta.stringToEnum(callbacks.CallbackType, callback_type_str) orelse {
        L.raiseErrorStr("Unknown callback type", .{});
        return 0;
    };

    L.pushValue(3);
    const ref = L.ref(zlua.registry_index) catch {
        L.raiseErrorStr("Failed to store callback", .{});
        return 0;
    };

    window_ptr.callbacks.set(callback_type, ref) catch {
        L.unref(zlua.registry_index, ref);
        L.raiseErrorStr("Failed to set callback", .{});
        return 0;
    };

    return 0;
}

pub fn handleCallback(
    active_window: *window.Window,
    callback: i32,
    context: *Context,
    extra_args: anytype,
    ) void {
    _ = context.lua.rawGetIndex(zlua.registry_index, callback);

    const userdata_ptr = context.lua.newUserdata(*window.Window, 0);
    userdata_ptr.* = active_window;

    _ = context.lua.getMetatableRegistry("Window");
    context.lua.setMetatable(-2);

    const fields = @typeInfo(@TypeOf(extra_args)).@"struct".fields;
    var total_args: i32 = 1;

    inline for (fields) |field| {
        const value = @field(extra_args, field.name);
        switch (@typeInfo(field.type)) {
            .int => context.lua.pushInteger(value),
            .float => context.lua.pushNumber(value),
            .array => context.lua.pushString(value),
            else => @compileError("Unsupported type for Lua callback"),
        }
        total_args += 1;
    }

    const args = zlua.Lua.ProtectedCallArgs {
        .args = total_args,
        .results = 0,
        .msg_handler = 0,
    };

    context.lua.protectedCall(args) catch |err| {
        std.debug.print("Lua callback error: {}\n", .{err});
        if (context.lua.isString(-1)) {
            const err_msg = context.lua.toString(-1) catch "unkown";
            std.debug.print("Error message: {s}\n", .{err_msg});
        }
        context.lua.pop(1);
    };
}
