const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;
const seat = wayland.client.seat;

const window = @import("./window.zig");
const OutputInfo = window.OutputInfo;

const Context = @import("./context.zig").Context;

const zlua = @import("zlua");
const Lua = zlua.Lua;

const PointerEvent = enum {
    Enter,
    Leave,
    Motion,
    Button,
};

pub fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, context: *Context) void {
    switch (event) {
        .enter => |enter| {
            for (context.windows.items) |*w| {
                if (w.surface == enter.surface) {
                    context.active_window = w;
                    if (w.callbacks.mouseenter != null) {
                        handleCallback(w, w.callbacks.mouseenter, context);
                    }
                    break;
                }
            }
        },
        .leave => {
            if (context.active_window) |active_window| {
                for (context.windows.items) |w| {
                    if (w.surface == active_window.surface) {
                        context.active_window = null;
                        if (active_window.callbacks.mouseleave != null) {
                            handleCallback(active_window, active_window.callbacks.mouseleave, context);
                        }
                        break;
                    }
                }
            }
        },
        .motion => {
            if (context.active_window) |active_window| {
                if (active_window.callbacks.mousemotion != null) {
                    handleCallback(active_window, active_window.callbacks.mousemotion, context);
                }
            }
        },
        .button => |button| {
            if (context.active_window) |active_window| {
                const btn = button.button;
                const state = button.state;

                if (btn == 272 and state == .pressed) { // Left click and pressed
                    if (active_window.callbacks.leftpress != null) {
                        handleCallback(active_window, active_window.callbacks.leftpress, context);
                    }
                } else if (btn == 272 and state == .released) { // Left click and released
                    if (active_window.callbacks.leftrelease != null) {
                        handleCallback(active_window, active_window.callbacks.leftrelease, context);
                    }
                }
            }
        },
        else => {},
    }
}

fn handleCallback(active_window: *window.Window, callback: ?i32, context: *Context) void {
    _ = context.lua.rawGetIndex(zlua.registry_index, callback.?);

    const userdata_ptr = context.lua.newUserdata(*window.Window, 0);
    userdata_ptr.* = active_window;

    _ = context.lua.getMetatableRegistry("Window");
    context.lua.setMetatable(-2);

    const args = zlua.Lua.ProtectedCallArgs {
        .args = 1, // One argument
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
