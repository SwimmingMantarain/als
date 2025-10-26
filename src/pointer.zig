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

const handleWindowCallback = @import("./lua/callbacks.zig").handleWindowCallback;
const handleWidgetCallback = @import("./lua/callbacks.zig").handleWidgetCallback;

pub fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, context: *Context) void {
    switch (event) {
        .enter => |enter| {
            for (context.windows.items) |w| {
                for (w.monitors.items) |*m| {
                    if (m.surface == enter.surface) {
                        context.active_window = w;
                        context.active_monitor = m;

                        if (w.callbacks.get(.mouseenter)) |callback| {
                            handleWindowCallback(w, callback, context, .{});
                        }
                        break;
                    }
                }
            }
        },
        .leave => |leave| {
            for (context.windows.items) |w| {
                for (w.monitors.items) |*m| {
                    if (m.surface == leave.surface) {
                        if (context.active_monitor) |active| {
                            if (active.surface == leave.surface) {
                                context.active_window = null;
                                context.active_monitor = null;
                            }
                        }
                        if (w.callbacks.get(.mouseleave)) |callback| {
                            handleWindowCallback(w, callback, context, .{});
                        }
                        break;
                    }
                }
            }
        },
        .motion => |motion| {
            if (context.active_window) |active_window| {
                if (active_window.hit(motion.surface_x.toDouble(), motion.surface_y.toDouble())) |widget| {
                    switch (widget.*) {
                        .label => |*l| {
                            if (l.callbacks.get(.mousemotion)) |callback| {
                                handleWidgetCallback(widget, callback, context, .{motion.surface_x.toInt(), motion.surface_y.toInt()});
                            }
                        },
                    }
                } else if (active_window.callbacks.get(.mousemotion)) |callback| {
                    handleWindowCallback(active_window, callback, context, .{});
                }
            }
        },
        .button => |button| {
            if (context.active_window) |active_window| {
                const btn = button.button;
                const state = button.state;

                if (btn == 272 and state == .pressed) { // Left click and pressed
                    if (active_window.callbacks.get(.leftpress)) |callback| {
                        handleWindowCallback(active_window, callback, context, .{});
                    }
                } else if (btn == 272 and state == .released) { // Left click and released
                    if (active_window.callbacks.get(.leftrelease)) |callback| {
                        handleWindowCallback(active_window, callback, context, .{});
                    }
                }
            }
        },
        else => {},
    }
}
