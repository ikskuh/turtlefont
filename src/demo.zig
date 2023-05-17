const std = @import("std");
const turtlefont = @import("turtlefont");
const args = @import("args");
const ProxyHead = @import("ProxyHead");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !u8 {
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var cli = args.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    const font: turtlefont.Font = blk: {
        var font_file = try std.fs.cwd().openFile(cli.options.font orelse @panic("missing font file parameters"), .{});
        defer font_file.close();

        var font_data = std.ArrayList(u8).init(allocator);
        defer font_data.deinit();

        try turtlefont.FontCompiler.compile(allocator, font_file.reader(), font_data.writer());

        const font_bits = try font_data.toOwnedSlice();
        errdefer allocator.free(font_bits);

        break :blk try turtlefont.Font.load(font_bits);
    };
    defer allocator.free(font.data);

    var head = ProxyHead.open() catch |err| {
        std.log.err("could not connect to Proxy: Head. Please make sure a head is running.", .{});
        std.log.err("internal error code: {s}", .{@errorName(err)});
        return 1;
    };
    defer head.close();

    const fb = try head.requestFramebuffer(.rgbx8888, 1280, 720, 200 * std.time.ns_per_ms);

    _ = fb;

    while (!head.input.keyboard.escape) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    return 0;
}

const CliOptions = struct {
    help: bool = false,

    font: ?[]const u8 = null,
};
