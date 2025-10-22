const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;
const Context = @import("./context.zig").Context;
const window = @import("./window.zig");

pub fn init(L: *Lua, context: *Context) void {
    L.pushLightUserdata(context);
    L.setField(zlua.registry_index, "context");

    registerModule(L);
}

fn registerModule(L: *Lua) void {
    // Create window object
    createWindowMetatable(L);

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaCreateWindow));
    L.setField(-2, "create_window");

    L.setGlobal("als");
}

fn createWindowMetatable(L: *Lua) void {
    L.newMetatable("Window") catch return;

    L.createTable(0, 1);

    L.pushFunction(zlua.wrap(luaSetCallback));
    L.setField(-2, "set_callback");

    L.pushFunction(zlua.wrap(luaSetWindowColor));
    L.setField(-2, "set_color");

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

fn luaSetWindowColor(L: *Lua) i32 {
    const window_ptr_ptr = L.checkUserdata(*window.Window, 1, "Window");
    const window_ptr = window_ptr_ptr.*;

    const color = L.toInteger(2) catch {
        L.raiseErrorStr("Expected Integer/Hexadecimal value (0xFFFFFFFF, 0xARGB)", .{});
        return 0;
    };

    window_ptr.setColor(@as(u32, @intCast(color)));

    return 0;
}

fn luaCreateWindow(L: *Lua) i32 {
    const width = L.toInteger(1) catch 100;
    const height = L.toInteger(2) catch 100;
    const x = L.toInteger(3) catch 0;
    const y = L.toInteger(4) catch 0;
    const onAllMonitors = L.toBoolean(5);

    const context = getContext(L) catch {
        _ = L.pushString("Failed to get context");
        L.raiseError();
        return 0;
    };

    const outputs = if (onAllMonitors)
        context.outputs.items
    else
        context.outputs.items[0..1];

    for (outputs) |output_info| {
        const w = window.Window.init(
            "als-window",
            @intCast(width), @intCast(height),
            @intCast(x), @intCast(y),
            context.display,
            context.compositor.?,
            context.shm.?,
            context.layer_shell.?,
            output_info.output
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
    }

    const window_ptr = &context.windows.items[context.windows.items.len - 1];
    const userdata_ptr = L.newUserdata(*window.Window, 0);
    userdata_ptr.* = window_ptr;

    _ = L.getMetatableRegistry("Window");
    L.setMetatable(-2);

    return 1;
}
