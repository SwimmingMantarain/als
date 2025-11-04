const std = @import("std");
const zlua = @import("zlua");

pub const CallbackType = enum {
    leftpress,
    leftrelease,
    mouseenter,
    mouseleave,
    mousemotion,
    key, 
};

pub const CallbackHandler = struct {
    lua: *zlua.Lua,
    callbacks: std.AutoHashMap(CallbackType, i32),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, lua: *zlua.Lua) CallbackHandler {
        return .{
            .lua = lua,
            .callbacks = std.AutoHashMap(CallbackType, i32).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CallbackHandler) void {
        var iter = self.callbacks.iterator();
        while (iter.next()) |entry| {
            self.lua.unref(zlua.registry_index, entry.value_ptr.*);
        }
        self.callbacks.deinit();
    }
    
    pub fn set(self: *CallbackHandler, callback_type: CallbackType, lua_ref: i32) !void {
        if (self.callbacks.get(callback_type)) |old_ref| {
            self.lua.unref(zlua.registry_index, old_ref);
        }
        
        try self.callbacks.put(callback_type, lua_ref);
    }
    
    pub fn get(self: *CallbackHandler, callback_type: CallbackType) ?i32 {
        return self.callbacks.get(callback_type);
    }
    
    pub fn remove(self: *CallbackHandler, callback_type: CallbackType) void {
        if (self.callbacks.fetchRemove(callback_type)) |kv| {
            self.lua.unref(zlua.registry_index, kv.value);
        }
    }
    
    pub fn has(self: *CallbackHandler, callback_type: CallbackType) bool {
        return self.callbacks.contains(callback_type);
    }
};
