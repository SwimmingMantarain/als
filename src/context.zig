const std = @import("std");
const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;
const seat = wayland.client.seat;
const zlua = @import("zlua");

const window = @import("./window.zig");

pub const Context = struct {
    display: *wl.Display,
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,
    outputs: std.ArrayList(window.OutputInfo),
    allocator: std.mem.Allocator,
    seat: ?*wl.Seat,
    pointer: ?*wl.Pointer,
    windows: std.ArrayList(window.Window),
    active_window: ?*window.Window,
    lua: *zlua.Lua,

    pub fn init(gpa: Allocator, display: *wl.Display, lua: *zlua.Lua) !Context {
        const context = Context{
            .display = display,
            .shm = null,
            .compositor = null,
            .layer_shell = null,
            .outputs = try .initCapacity(gpa, 5),
            .allocator = gpa,
            .seat = null,
            .pointer = null,
            .windows = try .initCapacity(gpa, 5),
            .active_window = null,
            .lua = lua,
        };
        
        return context;
    }

    pub fn deinit(self: *Context) void {
        self.outputs.deinit(self.allocator);
        self.windows.deinit(self.allocator);
    }
};
