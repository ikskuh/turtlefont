const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pkg_args = b.dependency("args", .{});
    const pkg_proxy_head = b.dependency("proxy_head", .{});

    const mod_turtlefont = b.addModule("turtlefont", .{
        .source_file = .{ .path = "src/turtlefont.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "demo",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/demo.zig" },
    });
    exe.addModule("turtlefont", mod_turtlefont);
    exe.addModule("args", pkg_args.module("args"));
    exe.addModule("ProxyHead", pkg_proxy_head.module("ProxyHead"));

    b.installArtifact(exe);
}
