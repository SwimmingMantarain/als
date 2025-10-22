const std = @import("std");
const posix = std.posix;

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

const xkb = @import("./context.zig").xkb;

pub fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, context: *Context) void {
    switch (event) {
        .keymap => |keymap| {
            const data = posix.mmap(
                null,
                keymap.size,
                posix.PROT.READ,
                .{ .TYPE = .PRIVATE },
                keymap.fd,
                0,
            ) catch return;

            const keymap_str: [*:0]const u8 = @ptrCast(data.ptr);

            const xkb_keymap = xkb.xkb_keymap_new_from_string(
                context.xkb_context,
                keymap_str,
                xkb.XKB_KEYMAP_FORMAT_TEXT_V1,
                xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );

            const xkb_state = xkb.xkb_state_new(xkb_keymap);

            context.xkb_keymap = xkb_keymap;
            context.xkb_state = xkb_state;
        },
        .key => |key| {
            if (context.active_window) |active_window| {
                if (active_window.callbacks.key) |callback| {
                    const keysym = xkb.xkb_state_key_get_one_sym(context.xkb_state, key.key + 8); // +8 for linux evdev
                    const keyutf32 = xkb.xkb_keysym_to_utf32(keysym);

                    std.debug.print("Key: {}\n", .{ keyutf32 });

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
