const std = @import("std");
const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;
const seat = wayland.client.seat;
const zlua = @import("zlua");

const window = @import("./window.zig");

pub const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
});

pub const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

pub const hb = @cImport({
    @cInclude("hb.h");
    @cInclude("hb-ft.h");
});

pub const Context = struct {
    display: *wl.Display,
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,
    outputs: std.ArrayList(window.OutputInfo),
    allocator: std.mem.Allocator,
    seat: ?*wl.Seat,
    pointer: ?*wl.Pointer,
    keyboard: ?*wl.Keyboard,
    windows: std.ArrayList(window.Window),
    active_window: ?*window.Window,
    active_monitor: ?*window.Monitor,
    lua: *zlua.Lua,

    // xkb shenanigans
    xkb_context: ?*xkb.xkb_context,
    xkb_keymap: ?*xkb.xkb_keymap,
    xkb_state: ?*xkb.xkb_state,

    pub fn init(gpa: Allocator, display: *wl.Display, lua: *zlua.Lua) !Context {
        const xkb_context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS);
        if (xkb_context == null) {
            return error.XkbContextFailed;
        }

        const context = Context{
            .display = display,
            .shm = null,
            .compositor = null,
            .layer_shell = null,
            .outputs = try .initCapacity(gpa, 5),
            .allocator = gpa,
            .seat = null,
            .pointer = null,
            .keyboard = null,
            .windows = try .initCapacity(gpa, 5),
            .active_window = null,
            .active_monitor = null,
            .lua = lua,
            .xkb_context = xkb_context,
            .xkb_keymap = null,
            .xkb_state = null,
        };
        
        return context;
    }

    pub fn deinit(self: *Context) void {
        if (self.xkb_state) |state| {
            xkb.xkb_state_unref(state);
        }
        if (self.xkb_keymap) |keymap| {
            xkb.xkb_keymap_unref(keymap);
        }
        if (self.xkb_context) |ctx| {
            xkb.xkb_context_unref(ctx);
        }

        self.outputs.deinit(self.allocator);
        self.windows.deinit(self.allocator);
    }
};
