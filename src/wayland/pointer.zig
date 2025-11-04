const std = @import("std");

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

const handleWindowCallback = @import("../lua/callbacks.zig").handleWindowCallback;
const handleWidgetCallback = @import("../lua/callbacks.zig").handleWidgetCallback;

pub fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, context: *Context) void {
    switch (event) {
        .enter => |enter| {
            for (context.monitors.monitors.items) |m| {
                for (m.windows.items) |w| {
                    if (w.surface == enter.surface) {
                        context.monitors.active_window = w;
                        context.monitors.active_monitor = m;
                        break;
                    }
                }
            }
        },
        .leave => |leave| {
            for (context.monitors.monitors.items) |m| {
                for (m.windows.items) |w| {
                    if (w.surface == leave.surface) {
                        context.monitors.active_window = null;
                        context.monitors.active_monitor = null;
                    }

                    if (w.callbacks.get(.mouseleave)) |callback| {
                        handleWindowCallback(w, callback, context, .{});
                    }

                    if (w.active_widget) |widget| {
                        switch (widget.*) {
                            .label => |*l| {
                                if (l.callbacks.get(.mouseleave)) |callback| {
                                    handleWidgetCallback(widget, callback, context, .{});
                                }   
                            },
                        }

                        w.active_widget = null;
                    }
                }
            }
        },
        .motion => |motion| {
            if (context.monitors.active_window) |active_window| {
                if (context.monitors.active_monitor) |_| {
                    const x = motion.surface_x.toDouble();
                    const y = motion.surface_y.toDouble();

                    if (active_window.mouseEnterWidget(x, y)) |widget| {
                        switch (widget.*) {
                            .label => |*l| {
                                if (l.callbacks.get(.mouseenter)) |callback| {
                                    handleWidgetCallback(widget, callback, context, .{ motion.surface_x.toInt(), motion.surface_y.toInt() });
                                }
                            },
                        }
                    }

                    if (active_window.mouseLeaveWidget(x, y)) |widget| {
                        switch (widget.*) {
                            .label => |*l| {
                                if (l.callbacks.get(.mouseleave)) |callback| {
                                    handleWidgetCallback(widget, callback, context, .{ motion.surface_x.toInt(), motion.surface_y.toInt() });
                                }
                            },
                        }
                    }
                }
            }
        },
        .button => |button| {
            if (context.monitors.active_window) |active_window| {
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
