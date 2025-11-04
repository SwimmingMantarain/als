const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("/usr/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml");

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 9);
    scanner.generate("xdg_wm_base", 1);
    scanner.generate("zwlr_layer_shell_v1", 4);

    const exe = b.addExecutable(.{
        .name = "als",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const lua_dep = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("wayland", wayland);
    exe.root_module.addImport("zlua", lua_dep.module("zlua"));
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("xkbcommon");
    exe.linkSystemLibrary("freetype2");
    exe.linkSystemLibrary("harfbuzz");

    b.installArtifact(exe);
}
