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

pub fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, context: *Context) void {
    switch (event) {
        .key => {
            if (context.active_window) |active_window| {
                if (active_window.callbacks.key) |callback| {
                    std.debug.print("Key!\n", .{});
                    handleCallback(active_window, callback, context);
                }
            }
        },
        else => {},
    }
}

fn handleCallback(active_window: *window.Window, callback: i32, context: *Context) void {
    _ = context.lua.rawGetIndex(zlua.registry_index, callback);

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
