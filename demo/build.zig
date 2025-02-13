const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tf_dep = b.dependency("turtlefont", .{});

    const tf_mod = tf_dep.module("turtlefont");

    const pkg_args = b.dependency("args", .{});
    const pkg_proxy_head = b.dependency("proxy_head", .{});

    const exe = b.addExecutable(.{
        .name = "demo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/demo.zig"),
    });
    exe.root_module.addImport("turtlefont", tf_mod);
    exe.root_module.addImport("args", pkg_args.module("args"));
    exe.root_module.addImport("ProxyHead", pkg_proxy_head.module("ProxyHead"));

    b.installArtifact(exe);
}
