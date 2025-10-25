const std = @import("std");
const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;
const seat = wayland.client.seat;
const zlua = @import("zlua");

const window = @import("./window.zig");
const widgets = @import("./widgets.zig");

pub const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
});

pub const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("hb.h");
    @cInclude("hb-ft.h");
});

pub const hb = ft;

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

    // FreeType shenanigans
    ft: ft.FT_Library,
    ft_face: ft.FT_Face,

    pub fn init(gpa: Allocator, display: *wl.Display, lua: *zlua.Lua) !Context {
        const xkb_context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS);
        if (xkb_context == null) {
            return error.XkbContextFailed;
        }

        var ft_lib: ft.FT_Library = undefined;
        if (ft.FT_Init_FreeType(&ft_lib) == 1) {
            return error.FreeTypeInitFailed;
        }

        const font_path = "/usr/share/fonts/Adwaita/AdwaitaMono-Regular.ttf";
        var ft_face: ft.FT_Face = undefined;
        if (ft.FT_New_Face(ft_lib, font_path, 0, &ft_face) == 1) {
            return error.FreeTypeFontFaceInitFailed;
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
            .ft = ft_lib,
            .ft_face = ft_face,
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

        if (self.ft_face) |ft_face| {
            _ = ft.FT_Done_Face(ft_face);
        }

        if (self.ft) |lib| {
            _ = ft.FT_Done_FreeType(lib);
        }

        self.outputs.deinit(self.allocator);
        self.windows.deinit(self.allocator);
    }
};
