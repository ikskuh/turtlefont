const std = @import("std");

pub const Font = struct {
    //! A container for a turtle vector graphics font.
    //! Contains an arbitrary amount of glyphs.

    /// Data encoding:
    /// ```
    /// struct {
    ///   font_id: u32 = 0x4c2b8688,
    ///   glyph_count: u32,
    ///   glyph_index: [glyph_count]struct {
    ///     oap: packed struct (u32) {
    ///         codepoint: u24,
    ///         advance: u8,
    ///     },
    ///     offset: u32,
    ///   },
    ///   glyph_code: [*]u8,
    /// }
    /// ```
    ///
    data: []const u8,

    pub fn load(buffer: []const u8) error{InvalidFont}!Font {
        if (buffer.len < 8)
            return error.InvalidFont;
        const magic = std.mem.readInt(u32, buffer[0..4], .little);
        const count = std.mem.readInt(u32, buffer[4..8], .little);
        if (magic != 0x4c2b8688)
            return error.InvalidFont;

        const limit_by_count = 8 + 8 * count;
        if (buffer.len < limit_by_count)
            return error.InvalidFont;

        for (0..count) |glyph_index| {
            const base = 8 + 8 * glyph_index;
            const cap = @as(CodepointAdvancePair, @bitCast(std.mem.readInt(u32, buffer[base..][0..4], .little)));
            const offset = std.mem.readInt(u32, buffer[base..][4..8], .little);
            if (cap.codepoint > std.math.maxInt(u21))
                return error.InvalidFont;
            if (limit_by_count + offset >= buffer.len)
                return error.InvalidFont;

            // bad sanity check: we expect a NUL terminated sequence of commands,
            // ignoring that 0x00 is a perfectly valid command paramter, but basic
            // sanitzing can't be that bad.
            var i: usize = limit_by_count + offset;
            while (i < buffer.len) : (i += 1) {
                if (buffer[i] == 0x00)
                    break;
            } else return error.InvalidFont;
        }

        return Font{
            .data = buffer,
        };
    }

    pub const Glyph = extern struct {
        codepoint: u32,
        advance: u8,
        offset: u32,
    };

    pub fn findGlyph(font: Font, codepoint: u21) ?Glyph {
        const total_count = std.mem.readInt(u32, font.data[4..8], .little);

        var base: usize = 0;
        var count: usize = total_count;

        while (count > 0) {
            const total_offset = 8 + 8 * (base + count / 2);
            const offset_advance_pair = std.mem.readInt(u32, font.data[total_offset..][0..4], .little);

            const cap = @as(CodepointAdvancePair, @bitCast(offset_advance_pair));

            if (cap.codepoint == codepoint) {
                const offset = std.mem.readInt(u32, font.data[total_offset..][4..8], .little);
                return Glyph{
                    .codepoint = cap.codepoint,
                    .offset = offset,
                    .advance = cap.advance,
                };
            }

            if (cap.codepoint < codepoint) {
                base += (count + 1) / 2;
                count = count / 2;
            } else {
                count /= 2;
            }
        } else return null;
    }

    pub fn getCode(font: Font, glyph: Glyph) [*]const u8 {
        const total_count = std.mem.readInt(u32, font.data[4..8], .little);
        const limit_by_count = 8 + 8 * total_count;

        return font.data.ptr + limit_by_count + glyph.offset;
    }
};

const CommandId = enum(u4) {
    end = 0,
    move_rel = 1,
    move_abs = 2,
    line_rel = 3,
    line_abs = 4,
    point = 5,

    pub fn coordinateType(cmd: CommandId) CoordinateType {
        return switch (cmd) {
            .end => .none,
            .move_rel => .relative,
            .move_abs => .absolute,
            .line_rel => .relative,
            .line_abs => .absolute,
            .point => .none,
        };
    }
};

const CoordinateType = enum { none, relative, absolute };

const EncodedCommand = packed struct(u8) {
    cmd: CommandId,
    pad: u4 = 0,
};

pub const FontCompiler = struct {
    const Point = struct {
        x: i8,
        y: i8,
    };

    const Command = union(enum) {
        move_rel: Point,
        move_abs: Point,
        line_rel: Point,
        line_abs: Point,
        point,
        advance: u8,
    };

    fn orderGlyphBuffer(_: void, a: GlyphBuffer, b: GlyphBuffer) bool {
        return a.codepoint < b.codepoint;
    }

    pub fn compile(allocator: std.mem.Allocator, src_stream: anytype, dst_stream: anytype) !void {
        var buffered_reader = std.io.bufferedReader(src_stream);

        const reader = buffered_reader.reader();

        var temp_storage = std.heap.ArenaAllocator.init(allocator);
        defer temp_storage.deinit();

        var list = std.ArrayList(GlyphBuffer).init(temp_storage.allocator());
        defer list.deinit();

        var line_buffer: [1024]u8 = undefined;
        while (try reader.readUntilDelimiterOrEof(&line_buffer, '\n')) |raw_line| {
            const line = std.mem.trim(u8, raw_line, "\r\n");
            if (line.len == 0)
                continue;

            var utf8_view = try std.unicode.Utf8View.init(line);

            var iterator = utf8_view.iterator();

            const codepoint = iterator.nextCodepoint() orelse return error.InvalidFormat;

            if (iterator.nextCodepoint() != @as(?u21, ':'))
                return error.InvalidFormat;

            var stream_buffer = std.ArrayList(u8).init(temp_storage.allocator());
            defer stream_buffer.deinit();

            var glyph_buffer = GlyphBuffer{
                .codepoint = codepoint,
                .code = undefined,
                .offset = undefined,
                .advance = undefined,
            };

            const meta = try compileGlyphScript(line[iterator.i..], stream_buffer.writer());
            glyph_buffer.advance = meta.advance;
            glyph_buffer.code = try stream_buffer.toOwnedSlice();

            try list.append(glyph_buffer);
        }

        std.sort.block(GlyphBuffer, list.items, {}, orderGlyphBuffer);

        var buffered_writer = std.io.bufferedWriter(dst_stream);
        const writer = buffered_writer.writer();

        try writer.writeInt(u32, 0x4c2b8688, .little);
        try writer.writeInt(u32, @as(u32, @intCast(list.items.len)), .little);

        var run_offset: u32 = 0;

        for (list.items) |glyph| {
            try writer.writeInt(u32, @as(u32, @bitCast(CodepointAdvancePair{
                .codepoint = glyph.codepoint,
                .advance = glyph.advance,
            })), .little);
            try writer.writeInt(u32, run_offset, .little);

            run_offset += @as(u32, @intCast(glyph.code.len));
        }

        for (list.items) |glyph| {
            try writer.writeAll(glyph.code);
        }

        try buffered_writer.flush();
    }

    pub const GlyphScriptMeta = struct {
        advance: u8,
    };

    pub fn compileGlyphScript(script: []const u8, writer: anytype) !GlyphScriptMeta {
        var meta: GlyphScriptMeta = .{ .advance = 0 };

        var decoder = GlyphScriptDecoder{ .slice = script };
        try decoder.compileCommandSequence(&meta.advance, writer);

        return meta;
    }

    pub const GlyphScriptDecoder = struct {
        slice: []const u8,
        i: usize = 0,

        fn compileCommandSequence(decoder: *GlyphScriptDecoder, advance: *u8, dst_writer: anytype) !void {
            var buffered_writer = std.io.bufferedWriter(dst_writer);
            const writer = buffered_writer.writer();

            advance.* = 0;

            while (try decoder.fetchCommand()) |cmd| {
                switch (cmd) {
                    .move_rel => |val| {
                        try writer.writeByte(@as(u8, @bitCast(EncodedCommand{ .cmd = .move_rel })));
                        try writePoint(writer, val);
                    },
                    .move_abs => |val| {
                        try writer.writeByte(@as(u8, @bitCast(EncodedCommand{ .cmd = .move_abs })));
                        try writePoint(writer, val);
                    },
                    .line_rel => |val| {
                        try writer.writeByte(@as(u8, @bitCast(EncodedCommand{ .cmd = .line_rel })));
                        try writePoint(writer, val);
                    },
                    .line_abs => |val| {
                        try writer.writeByte(@as(u8, @bitCast(EncodedCommand{ .cmd = .line_abs })));
                        try writePoint(writer, val);
                    },
                    .point => try writer.writeByte(@as(u8, @bitCast(EncodedCommand{ .cmd = .point }))),
                    .advance => |val| advance.* = val,
                }
            }
            try writer.writeByte(@as(u8, @bitCast(EncodedCommand{ .cmd = .end })));
            try buffered_writer.flush();
        }

        fn writePoint(writer: anytype, pt: Point) !void {
            try writer.writeInt(i8, pt.x, .little);
            try writer.writeInt(i8, pt.y, .little);
        }

        fn fetchCommand(decoder: *GlyphScriptDecoder) !?Command {
            const c = decoder.fetchChar() orelse return null;

            return switch (c) {
                'a' => Command{ .advance = try decoder.fetchNumber(u8) },

                'm' => Command{ .move_rel = try decoder.fetchPoint() },
                'M' => Command{ .move_abs = try decoder.fetchPoint() },

                'p' => Command{ .line_rel = try decoder.fetchPoint() },
                'P' => Command{ .line_abs = try decoder.fetchPoint() },

                'd' => .point,

                else => return error.InvalidCommand,
            };
        }

        fn fetchPoint(decoder: *GlyphScriptDecoder) !Point {
            const x = try decoder.fetchNumber(i8);
            const y = try decoder.fetchNumber(i8);
            return Point{ .x = x, .y = y };
        }

        fn fetchNumber(decoder: *GlyphScriptDecoder, comptime T: type) error{ MissingNumber, InvalidCharacter, Overflow }!T {
            var factor: i16 = 1;
            var c = decoder.fetchChar() orelse return error.MissingNumber;
            if (c == '-') {
                factor = -1;

                c = decoder.fetchChar() orelse return error.MissingNumber;
            }

            const digit = std.fmt.parseInt(u4, &.{c}, 16) catch return error.InvalidCharacter;

            return std.math.cast(T, factor * digit) orelse return error.Overflow;
        }

        fn fetchChar(decoder: *GlyphScriptDecoder) ?u8 {
            if (decoder.i >= decoder.slice.len)
                return null;

            while (true) {
                const c = decoder.slice[decoder.i];
                decoder.i += 1;
                switch (c) {
                    ' ' => continue,
                    '\n' => continue,
                    '\r' => continue,
                    '\t' => continue,
                    else => return c,
                }
            }
        }
    };

    const GlyphBuffer = struct {
        codepoint: u21,
        code: []u8,
        offset: u32,
        advance: u8,
    };
};

pub const RasterOptions = struct {
    font_size: u15 = 16,
    dot_size: u15 = 0,
    stroke_size: u15 = 1,
    line_spacing: u32 = 1200, // 1.2

    pub fn lineHeight(options: RasterOptions) u15 {
        return @as(u15, @intCast(125 * options.font_size * options.line_spacing / 100_000));
    }

    pub fn scale(options: RasterOptions, v: i16) i16 {
        return @divTrunc((options.font_size * v + 4), 8); // 8 is encoded font height
    }

    pub fn scaleX(options: RasterOptions, x: i16) i16 {
        return options.scale(x);
    }

    pub fn scaleY(options: RasterOptions, y: i16) i16 {
        return options.scale(y - 2); // 2 is descender
    }
};

pub fn Rasterizer(
    comptime Context: type,
    comptime Color: type,
    comptime setPixel: fn (Context, x: i16, y: i16, Color) void,
) type {
    return struct {
        const Rast = @This();
        const Point = struct {
            x: i16,
            y: i16,
        };
        const Options = RasterOptions;

        context: Context,

        pub fn init(ctx: Context) Rast {
            return .{ .context = ctx };
        }

        fn put(raster: Rast, x: i16, y: i16, c: Color) void {
            setPixel(raster.context, x, y, c);
        }

        fn putStroke(raster: Rast, options: Options, x: i16, y: i16, c: Color) void {
            for (0..options.stroke_size) |i| {
                for (0..(options.stroke_size + 1) / 2) |j| {
                    raster.put(x + @as(u15, @intCast(i)), y + @as(u15, @intCast(j)), c);
                }
            }
        }

        pub fn render(raster: Rast, x: i16, y: i16, string: []const u8, font: Font, color: Color, options: Options) void {
            var view = std.unicode.Utf8View.initUnchecked(string);
            var iter = view.iterator();

            const replacement_glyph = font.findGlyph('�') orelse font.findGlyph('?');

            const line_height = options.lineHeight();

            var px = x;
            var py = y;
            while (iter.nextCodepoint()) |codepoint| {
                if (codepoint == '\n') {
                    px = x;
                    py += line_height;
                    continue;
                }

                const glyph: Font.Glyph = font.findGlyph(codepoint) orelse replacement_glyph orelse continue;

                raster.renderGlyph(options, px, py, color, font.getCode(glyph));

                px += options.scaleX(glyph.advance);
            }
        }

        pub fn renderGlyph(raster: Rast, options: Options, tx: i16, ty: i16, color: Color, glyph_code: [*]const u8) void {
            var prev = Point{ .x = 0, .y = 0 };
            var pos = Point{ .x = 0, .y = 0 };

            var reader = Reader{ .ptr = glyph_code };
            while (reader.fetchCommand()) |cmd| {
                switch (cmd.coordinateType()) {
                    .none => {},
                    .relative => {
                        const delta = reader.fetchPoint();
                        pos.x +|= delta.x;
                        pos.y +|= delta.y;
                    },
                    .absolute => pos = reader.fetchPoint(),
                }

                switch (cmd) {
                    .end => unreachable,

                    .move_rel, .move_abs => {},

                    .line_rel, .line_abs => raster.line(
                        options,
                        tx + options.scaleX(prev.x),
                        ty - options.scaleY(prev.y),
                        tx + options.scaleX(pos.x),
                        ty - options.scaleY(pos.y),
                        color,
                    ),

                    .point => raster.dot(
                        options,
                        tx + options.scaleX(pos.x),
                        ty - options.scaleY(pos.y),
                        color,
                    ),
                }
                prev = pos;
            }
        }

        const Reader = struct {
            ptr: [*]const u8,

            fn fetchCommand(reader: *Reader) ?CommandId {
                const ec = @as(EncodedCommand, @bitCast(reader.ptr[0]));
                reader.ptr += 1;
                if (ec.cmd == .end)
                    return null;
                return ec.cmd;
            }
            fn fetchPoint(reader: *Reader) Point {
                const x = @as(i8, @bitCast(reader.ptr[0]));
                const y = @as(i8, @bitCast(reader.ptr[1]));
                reader.ptr += 2;
                return Point{ .x = x, .y = y };
            }
        };

        fn line(raster: Rast, options: Options, x0: i16, y0: i16, x1: i16, y1: i16, color: Color) void {
            const dx = @as(i16, @intCast(if (x1 > x0) x1 - x0 else x0 - x1));
            const dy = -@as(i16, @intCast(if (y1 > y0) y1 - y0 else y0 - y1));

            const sx = if (x0 < x1) @as(i16, 1) else @as(i16, -1);
            const sy = if (y0 < y1) @as(i16, 1) else @as(i16, -1);

            var err = dx + dy;

            var x = x0;
            var y = y0;

            while (true) {
                raster.putStroke(options, x, y, color);

                if (x == x1 and y == y1) {
                    break;
                }

                const e2 = 2 * err;
                if (e2 > dy) { // e_xy+e_x > 0
                    err += dy;
                    x += sx;
                }
                if (e2 < dx) { // e_xy+e_y < 0
                    err += dx;
                    y += sy;
                }
            }
        }

        fn dot(raster: Rast, options: Options, x: i16, y: i16, color: Color) void {
            const size2 = options.dot_size * options.dot_size;
            var dy: i16 = -@as(i16, options.dot_size);
            while (dy <= options.dot_size) : (dy += 1) {
                var dx: i16 = -@as(i16, options.dot_size);
                while (dx <= options.dot_size) : (dx += 1) {
                    if (dx * dx + dy * dy <= size2) {
                        raster.put(x + dx, y + dy, color);
                    }
                }
            }
        }
    };
}

pub const CodepointAdvancePair = packed struct(u32) {
    codepoint: u24,
    advance: u8,
};
