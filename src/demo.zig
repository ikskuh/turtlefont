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

    if (cli.options.output) |output_file_name| {
        var font_file = try std.fs.cwd().createFile(output_file_name, .{});
        defer font_file.close();

        try font_file.writeAll(font.data);
    }

    var head = ProxyHead.open() catch |err| {
        std.log.err("could not connect to Proxy: Head. Please make sure a head is running.", .{});
        std.log.err("internal error code: {s}", .{@errorName(err)});
        return 1;
    };
    defer head.close();

    const fb = try head.requestFramebuffer(.rgbx8888, 400, 300, 200 * std.time.ns_per_ms);

    const rast = Rasterizer.init(fb);
    var cfg = turtlefont.RasterOptions{};

    while (!head.input.keyboard.escape) {
        clear(fb, .{ .r = 0, .g = 0, .b = 0 });

        if (head.input.keyboard.up) {
            cfg.font_size += 1;
        }

        if (head.input.keyboard.down and cfg.font_size > 8) {
            cfg.font_size -= 1;
        }

        if (head.input.keyboard.right) {
            cfg.stroke_size += 1;
        }

        if (head.input.keyboard.left and cfg.stroke_size > 1) {
            cfg.stroke_size -= 1;
        }

        rast.render(
            10,
            10 + cfg.lineHeight(),
            "Hello, World!",
            font,
            .{ .r = 0xFF, .g = 0x00, .b = 0x00 },
            cfg,
        );

        std.time.sleep(100 * std.time.ns_per_ms);
    }

    return 0;
}

const CliOptions = struct {
    help: bool = false,

    font: ?[]const u8 = null,
    output: ?[]const u8 = null,
};

const Color = ProxyHead.ColorFormat.RGBX8888;

fn clear(fb: ProxyHead.Framebuffer(Color), color: Color) void {
    for (0..fb.height) |y| {
        for (0..fb.width) |x| {
            fb.base[y * fb.stride + x] = color;
        }
    }
}

fn setPixel(fb: ProxyHead.Framebuffer(Color), x: i16, y: i16, color: Color) void {
    const px = std.math.cast(usize, x) orelse return;
    const py = std.math.cast(usize, y) orelse return;

    if (px >= fb.width) return;
    if (py >= fb.height) return;

    fb.base[fb.stride * py + px] = color;
}

const Rasterizer = turtlefont.Rasterizer(
    ProxyHead.Framebuffer(Color),
    ProxyHead.ColorFormat.RGBX8888,
    setPixel,
);
