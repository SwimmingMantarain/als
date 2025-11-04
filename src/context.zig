const std = @import("std");
const Allocator = std.mem.Allocator;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;
const seat = wayland.client.seat;
const zlua = @import("zlua");

const window = @import("./wayland/window.zig");
const luaWindow = @import("./lua/api_window.zig").luaWindow;
const widgets = @import("./widgets/widgets.zig");

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

pub const WaylandContext = struct {
    display: *wl.Display,
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,

    pub fn new(display: *wl.Display) WaylandContext {
        return .{
            .display = display,
            .shm = null,
            .compositor = null,
            .layer_shell = null,
        };
    }
};

pub const InputContext = struct {
    seat: ?*wl.Seat,
    pointer: ?*wl.Pointer,
    keyboard: ?*wl.Keyboard,
    xkb_context: ?*xkb.xkb_context,
    xkb_keymap: ?*xkb.xkb_keymap,
    xkb_state: ?*xkb.xkb_state,

    pub fn new() anyerror!InputContext {
        const xkb_context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS);
        if (xkb_context == null) return error.XkbContextFailed;

        return .{
            .seat = null,
            .pointer = null,
            .keyboard = null,
            .xkb_context = xkb_context,
            .xkb_keymap = null,
            .xkb_state = null,
        };
    }

    pub fn deinit(self: *InputContext) void {
        if (self.xkb_state) |state| xkb.xkb_state_unref(state);
        if (self.xkb_keymap) |keymap| xkb.xkb_keymap_unref(keymap);
        if (self.xkb_context) |ctx| xkb.xkb_context_unref(ctx);
    }
};

pub const RenderContext = struct {
    ft: ft.FT_Library,
    ft_face: ft.FT_Face,

    pub fn new() anyerror!RenderContext {
        var ft_lib: ft.FT_Library = undefined;
        if (ft.FT_Init_FreeType(&ft_lib) == 1) return error.FreeTypeInitFailed;


        const font_path = "/usr/share/fonts/Adwaita/AdwaitaMono-Regular.ttf";
        var ft_face: ft.FT_Face = undefined;
        if (ft.FT_New_Face(ft_lib, font_path, 0, &ft_face) == 1) return error.FreeTypeFontFaceInitFailed;

        return .{
            .ft = ft_lib,
            .ft_face = ft_face,
        };
    }

    pub fn deinit(self: *RenderContext) void {
        if (self.ft_face) |ft_face| _ = ft.FT_Done_Face(ft_face);
        if (self.ft) |lib| _ = ft.FT_Done_FreeType(lib);
    }
};

pub const MonitorManager = struct {
    monitors: std.ArrayList(*window.Monitor),
    outputs: std.ArrayList(window.OutputInfo),
    active_monitor: ?*window.Monitor,
    active_window: ?*window.Window,
    window_instance_count: u32,

    pub fn new(gpa: std.mem.Allocator) anyerror!MonitorManager {
        const monitors = try std.ArrayList(*window.Monitor).initCapacity(gpa, 5);
        const outputs = try std.ArrayList(window.OutputInfo).initCapacity(gpa, 5);

        return .{
            .monitors = monitors,
            .outputs = outputs,
            .active_monitor = null,
            .active_window = null,
            .window_instance_count = 0,
        };
    }

    pub fn init(self: *MonitorManager, context: *Context) anyerror!void {
        var i: u32 = 0;
        for (self.outputs.items) |output| {
            const monitor = try window.Monitor.new(output, i, context);
            const mon_ptr = try context.gpa.create(window.Monitor);

            mon_ptr.* = monitor;

            try self.monitors.append(context.gpa, mon_ptr);
            i += 1;
        }
    }

    pub fn new_window(
        self: *MonitorManager,
        gpa: std.mem.Allocator,
        w: i64,
        h: i64,
        monitor_list: []const u8,
        context: *Context,
    ) anyerror!*luaWindow {
        if (!std.mem.eql(u8, monitor_list, "all")) {
            var it = std.mem.splitScalar(u8, monitor_list, ',');
            var monitors = try std.ArrayList(*window.Monitor).initCapacity(gpa, 5);

            while (it.next()) |part| {
                try monitors.append(gpa, try self.get_monitor(part));
            }

            var windows = try std.ArrayList(*window.Window).initCapacity(gpa, monitors.items.len);

            for (monitors.items) |monitor| {
                try windows.append(gpa, try monitor.new_window(w, h, self.window_instance_count));
            }

            const lwin = luaWindow{
                .id = self.window_instance_count,
                .context = context,
            };

            const lwin_ptr = try gpa.create(luaWindow);
            lwin_ptr.* = lwin;

            self.window_instance_count += 1;

            return lwin_ptr;

        } else {
            var windows = try std.ArrayList(*window.Window).initCapacity(gpa, self.monitors.items.len);

            for (self.monitors.items) |monitor| {
                try windows.append(gpa, try monitor.new_window(w, h, self.window_instance_count));
            }

            const lwin = luaWindow{
                .id = self.window_instance_count,
                .context = context,
            };

            const lwin_ptr = try gpa.create(luaWindow);
            lwin_ptr.* = lwin;

            self.window_instance_count += 1;

            return lwin_ptr;
        }


    }

    fn get_monitor(self: *MonitorManager, name: []const u8) anyerror!*window.Monitor {
        for (self.monitors.items) |monitor| {
            if (std.mem.eql(u8, name, monitor.output.name)) return monitor;
        }

        std.debug.print("Unknown monitor name: `{s}`\n", .{name});
        return error.UnknownMonitor;
    }

    pub fn get_windows(self: *MonitorManager, id: u32, context: *Context) anyerror!std.ArrayList(*window.Window) {
        var windows = try std.ArrayList(*window.Window).initCapacity(context.gpa, self.monitors.items.len);

        for (self.monitors.items) |monitor| {
            if (monitor.get_window(id)) |w| {
                try windows.append(context.gpa, w);
            }
        }

        if (windows.items.len == 0) {
            windows.deinit(context.gpa);
            return error.UnknownWindowID;
        }

        return windows;
    }

    pub fn deinit(self: *MonitorManager, gpa: std.mem.Allocator) void {
        for (self.outputs.items) |*out| {
            if (out.name.len != 0) gpa.free(out.name);
        }

        self.outputs.deinit(gpa);

        for (self.monitors.items) |monitor| {
            monitor.deinit();
        }

        self.monitors.deinit(gpa);
    }
};

pub const Context = struct {
    wayland: WaylandContext,
    input: InputContext,
    render: RenderContext,
    monitors: MonitorManager,
    gpa: std.mem.Allocator,
    lua: *zlua.Lua,

    pub fn init(gpa: Allocator, display: *wl.Display, lua: *zlua.Lua) anyerror!Context {
        const wayland_ctx = WaylandContext.new(display);
        const input_ctx = try InputContext.new();
        const render_ctx = try RenderContext.new();
        const monitor_ctx = try MonitorManager.new(gpa);

        const context = Context{
            .wayland = wayland_ctx,
            .input = input_ctx,
            .render = render_ctx,
            .monitors = monitor_ctx,
            .gpa = gpa,
            .lua = lua,
        };

        return context;
    }

    pub fn deinit(self: *Context) void {
        self.monitors.deinit(self.gpa);
        self.input.deinit();
        self.render.deinit();
    }
};
