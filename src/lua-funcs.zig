const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const Context = @import("./context.zig").Context;
const window = @import("./window.zig");
const widgets = @import("./widgets.zig");

pub fn init(L: *Lua, context: *Context) void {
    L.pushLightUserdata(context);
    L.setField(zlua.registry_index, "context");

    registerModule(L);
}

fn registerModule(L: *Lua) void {
    // Create window object
    createWindowMetatable(L);

    // Create label object
    createLabelMetatable(L);

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaCreateWindow));
    L.setField(-2, "create_window");

    L.setGlobal("als");

    // Global manim like enum stuff
    L.pushInteger(1);
    L.setGlobal("UP");

    L.pushInteger(2);
    L.setGlobal("DOWN");

    L.pushInteger(3);
    L.setGlobal("LEFT");

    L.pushInteger(4);
    L.setGlobal("RIGHT");

    L.pushInteger(0);
    L.setGlobal("CENTER");

    L.pushInteger(-1);
    L.setGlobal("SCREEN_WIDTH");
    
    L.pushInteger(-1);
    L.setGlobal("SCREEN_HEIGHT");
}

fn createWindowMetatable(L: *Lua) void {
    L.newMetatable("Window") catch return;

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaSetCallback));
    L.setField(-2, "set_callback");

    L.pushFunction(zlua.wrap(luaSetWindowEdge));
    L.setField(-2, "to_edge");

    L.pushFunction(zlua.wrap(luaWindowNewLabel));
    L.setField(-2, "new_label");

    L.setField(-2, "__index");

    L.pop(1);
}

fn createLabelMetatable(L: *Lua) void {
    L.newMetatable("Label") catch return;

    L.createTable(0, 1);

    L.setField(-2, "__index");

    L.pop(1);
}

fn getContext(L: *Lua) anyerror!*Context {
    _ = L.getField(zlua.registry_index, "context");
    const context = try L.toUserdata(*Context, -1);
    L.pop(1);
    return @ptrCast(@alignCast(context));
}

fn luaSetCallback(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const callback_type = L.toString(2) catch {
        L.raiseErrorStr("Expected string as 2nd arg", .{});
        return 0;
    };

    if (!L.isFunction(3)) {
        L.raiseErrorStr("Expected func as 3rd arg", .{});
        return 0;
    }

    L.pushValue(3);
    const ref = L.ref(zlua.registry_index) catch {
        L.raiseErrorStr("Failed to store callback", .{});
        return 0;
    };

    const callbacks_type = @typeInfo(window.Callbacks).@"struct";
    var callback_found = false;

    inline for (callbacks_type.fields) |field| {
        if (std.mem.eql(u8, callback_type, field.name)) {
            if (@field(window_ptr.callbacks, field.name)) |old_ref| {
                L.unref(zlua.registry_index, old_ref);
            }

            @field(window_ptr.callbacks, field.name) = ref;
            callback_found = true;
            break;
        }
    }

    if (!callback_found) {
        L.unref(zlua.registry_index, ref);
        L.raiseErrorStr("Unknown callback type", .{});
        return 0;
    }

    return 0;
}

fn luaSetWindowEdge(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const edge = L.toInteger(2) catch 0; // 0 -> center

    window_ptr.toEdge(@intCast(edge));

    return 0;
}

fn luaWindowNewLabel(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const text = L.toString(2) catch "label";
    const font_size = L.toInteger(3) catch 16;
    const padding = L.toInteger(4) catch 0;
    const alignment = L.toInteger(5) catch 0; // 0 -> center

    const label = window_ptr.newLabel(
        text,
        @intCast(font_size),
        @intCast(padding), @intCast(alignment),
    );

    context.widgets.append(context.allocator, label) catch {
        L.raiseErrorStr("Failed to append label", .{});
        return 0;
    };

    const label_ptr = &context.widgets.items[context.widgets.items.len - 1];
    const userdata_ptr = L.newUserdata(*widgets.Label, 0);
    userdata_ptr.* = label_ptr;

    _ = L.getMetatableRegistry("Label");
    L.setMetatable(-2);

    return 1;
}

fn luaCreateWindow(L: *Lua) i32 {
    const width = L.toInteger(1) catch 100;
    const height = L.toInteger(2) catch 100;
    const bgcol = L.toInteger(3) catch 0xFF000000;
    const onAllMonitors = L.toBoolean(4);

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const outputs = if (onAllMonitors)
        context.outputs.items
    else
        context.outputs.items[0..1];

    const w = window.Window.init(
        "als-window",
        @intCast(width), @intCast(height),
        @intCast(bgcol),
        context,
        outputs,
    ) catch {
        _ = L.pushString("Failed to create window");
        L.raiseError();
        return 0;
    };

    context.windows.append(context.allocator, w) catch {
        _ = L.pushString("Failed to append window");
        L.raiseError();
        return 0;
    };

    const window_ptr = &context.windows.items[context.windows.items.len - 1];
    const userdata_ptr = L.newUserdata(*window.Window, 0);
    userdata_ptr.* = window_ptr;

    _ = L.getMetatableRegistry("Window");
    L.setMetatable(-2);

    return 1;
}

pub fn handleCallback(
    active_window: *window.Window,
    callback: i32,
    context: *Context,
    extra_args: anytype,
    ) void {
    _ = context.lua.rawGetIndex(zlua.registry_index, callback);

    const userdata_ptr = context.lua.newUserdata(*window.Window, 0);
    userdata_ptr.* = active_window;

    _ = context.lua.getMetatableRegistry("Window");
    context.lua.setMetatable(-2);

    const fields = @typeInfo(@TypeOf(extra_args)).@"struct".fields;
    var total_args: i32 = 1;

    inline for (fields) |field| {
        const value = @field(extra_args, field.name);
        switch (@typeInfo(field.type)) {
            .int => context.lua.pushInteger(value),
            .float => context.lua.pushNumber(value),
            .array => context.lua.pushString(value),
            else => @compileError("Unsupported type for Lua callback"),
        }
        total_args += 1;
    }

    const args = zlua.Lua.ProtectedCallArgs {
        .args = total_args,
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
