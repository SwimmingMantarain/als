const std = @import("std");
const mem = std.mem;
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
const als = @import("./lua/bindings.zig");

const pointerListener = @import("./pointer.zig").pointerListener;
const keyboardListener = @import("./keyboard.zig").keyboardListener;

pub fn main() anyerror!void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lua = try Lua.init(allocator);
    defer lua.deinit();
    lua.openLibs(); // load standard library

    var context = try Context.init(allocator, display, lua);
    defer context.deinit();

    als.init(lua, &context); // Register my API

    registry.setListener(*Context, registryListener, &context);

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed; // Get Globals
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed; // Get Output Info
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed; // Give outputs some time to think

    const config_path = "./config.lua"; // Testing purposes only
    lua.doFile(config_path) catch |err| {
        std.debug.print("Failed to load config: {}\n", .{err});

        if (lua.isString(-1)) {
            const err_msg = lua.toString(-1) catch "unkown error";
            std.debug.print("Lua error: {s}\n", .{err_msg});
        }

        return error.ConfigLoadFailed;
    };

    while (true) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;

        for (context.windows.items) |w| {
            try w.update(display);
        }

        std.Thread.sleep(16_000_000); // ~60fps (16ms)
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.interface.name) == .eq) {
                context.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const output = registry.bind(global.name, wl.Output, 1) catch return;

                const info = OutputInfo{ .output = output };
                context.outputs.append(context.allocator, info) catch return;

                const stored_info = &context.outputs.items[context.outputs.items.len - 1];
                output.setListener(*OutputInfo, outputListener, stored_info);
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                context.seat = registry.bind(global.name, wl.Seat, 1) catch return;
                context.seat.?.setListener(*Context, seatListener, context);
            }
        },
        .global_remove => {},
    }
}

fn outputListener(_: *wl.Output, event: wl.Output.Event, info: *OutputInfo) void {
    switch (event) {
        .mode => |mode| {
            info.width = mode.width;
            info.height = mode.height;
        },
        .done => {
            info.ready = true;
        },
        else => {},
    }
}

fn seatListener(seat_: *wl.Seat, event: wl.Seat.Event, context: *Context) void {
    switch (event) {
        .capabilities => |caps| {
            if (caps.capabilities.pointer) { // Check for pointer
                context.pointer = seat_.getPointer() catch return;
                context.pointer.?.setListener(*Context, pointerListener, context);
            }

            if (caps.capabilities.keyboard) { // Check for keyboard
                context.keyboard = seat_.getKeyboard() catch return;
                context.keyboard.?.setListener(*Context, keyboardListener, context);
            }
        },
        .name => {},
    }
}
