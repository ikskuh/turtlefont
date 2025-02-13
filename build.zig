const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("turtlefont", .{
        .root_source_file = b.path("src/turtlefont.zig"),
    });
}
