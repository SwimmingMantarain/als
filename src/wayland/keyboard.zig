const std = @import("std");
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;
const seat = wayland.client.seat;

const window = @import("./window.zig");
const OutputInfo = window.OutputInfo;

const Context = @import("../context.zig").Context;

const zlua = @import("zlua");
const Lua = zlua.Lua;

const xkb = @import("../context.zig").xkb;

const handleWindowCallback = @import("../lua/callbacks.zig").handleWindowCallback;

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
                context.input.xkb_context,
                keymap_str,
                xkb.XKB_KEYMAP_FORMAT_TEXT_V1,
                xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );

            const xkb_state = xkb.xkb_state_new(xkb_keymap);

            context.input.xkb_keymap = xkb_keymap;
            context.input.xkb_state = xkb_state;
        },
        .key => |key| {
            if (context.monitors.active_window) |active_window| {
                if (active_window.callbacks.get(.key)) |callback| {
                    const keysym = xkb.xkb_state_key_get_one_sym(context.input.xkb_state, key.key + 8); // +8 for linux evdev
                    const keyutf32 = xkb.xkb_keysym_to_utf32(keysym);

                    handleWindowCallback(active_window, callback, context, .{ keyutf32 });
                }
            }
        },
        else => {},
    }
}
