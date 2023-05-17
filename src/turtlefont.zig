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
        const magic = std.mem.readIntLittle(u32, buffer[0..4]);
        const count = std.mem.readIntLittle(u32, buffer[4..8]);
        if (magic != 0x4c2b8688)
            return error.InvalidFont;

        const limit_by_count = 8 + 8 * count;
        if (buffer.len < limit_by_count)
            return error.InvalidFont;

        for (0..count) |glyph_index| {
            const base = 8 + 8 * glyph_index;
            const cap = @bitCast(CodepointAdvancePair, std.mem.readIntLittle(u32, buffer[base..][0..4]));
            const offset = std.mem.readIntLittle(u32, buffer[base..][4..8]);
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

    const Glyph = extern struct {
        codepoint: u32,
        advance: u8,
        offset: u32,
    };

    pub fn findGlyph(font: Font, codepoint: u21) ?Glyph {
        const total_count = std.mem.readIntLittle(u32, font.data[4..8]);

        var base: usize = 0;
        var count: usize = total_count;

        while (count > 0) {
            const total_offset = 8 + 8 * (base + count / 2);
            const offset_advance_pair = std.mem.readIntLittle(u32, font.data[total_offset..][0..4]);

            const cap = @bitCast(CodepointAdvancePair, offset_advance_pair);

            if (cap.codepoint == codepoint) {
                const offset = std.mem.readIntLittle(u32, font.data[total_offset..][4..8]);
                return Glyph{
                    .codepoint = cap.codepoint,
                    .offset = offset,
                    .advance = cap.advance,
                };
            }

            if (cap.codepoint < codepoint) {
                base += count / 2;
                count -= count / 2;
            } else {
                count /= 2;
            }
        } else return null;
    }
};

const CommandId = enum(u4) {
    move_rel = 0,
    move_abs = 1,
    line_rel = 2,
    line_abs = 3,
    point = 4,
};

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

    const Decoder = struct {
        slice: []const u8,
        i: usize = 0,

        fn compileCommandSequence(decoder: *Decoder, advance: *u8, dst_writer: anytype) !void {
            var buffered_writer = std.io.bufferedWriter(dst_writer);
            const writer = buffered_writer.writer();

            advance.* = 0;

            while (try decoder.fetchCommand()) |cmd| {
                switch (cmd) {
                    .move_rel => |val| {
                        try writer.writeByte(@bitCast(u8, EncodedCommand{ .cmd = .move_rel }));
                        try writePoint(writer, val);
                    },
                    .move_abs => |val| {
                        try writer.writeByte(@bitCast(u8, EncodedCommand{ .cmd = .move_abs }));
                        try writePoint(writer, val);
                    },
                    .line_rel => |val| {
                        try writer.writeByte(@bitCast(u8, EncodedCommand{ .cmd = .line_rel }));
                        try writePoint(writer, val);
                    },
                    .line_abs => |val| {
                        try writer.writeByte(@bitCast(u8, EncodedCommand{ .cmd = .line_abs }));
                        try writePoint(writer, val);
                    },
                    .point => try writer.writeByte(@bitCast(u8, EncodedCommand{ .cmd = .point })),
                    .advance => |val| advance.* = val,
                }
            }

            try buffered_writer.flush();
        }

        fn writePoint(writer: anytype, pt: Point) !void {
            try writer.writeIntLittle(i8, pt.x);
            try writer.writeIntLittle(i8, pt.y);
        }

        fn fetchCommand(decoder: *Decoder) !?Command {
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

        fn fetchPoint(decoder: *Decoder) !Point {
            const x = try decoder.fetchNumber(i8);
            const y = try decoder.fetchNumber(i8);
            return Point{ .x = x, .y = y };
        }

        fn fetchNumber(decoder: *Decoder, comptime T: type) error{ MissingNumber, InvalidCharacter, Overflow }!T {
            var factor: i16 = 1;
            var c = decoder.fetchChar() orelse return error.MissingNumber;
            if (c == '-') {
                factor = -1;

                c = decoder.fetchChar() orelse return error.MissingNumber;
            }

            const digit = std.fmt.parseInt(u4, &.{c}, 16) catch return error.InvalidCharacter;

            return std.math.cast(T, factor * digit) orelse return error.Overflow;
        }

        fn fetchChar(decoder: *Decoder) ?u8 {
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

            var codepoint = iterator.nextCodepoint() orelse return error.InvalidFormat;

            if (iterator.nextCodepoint() != @as(?u21, ':'))
                return error.InvalidFormat;

            var stream_buffer = std.ArrayList(u8).init(temp_storage.allocator());
            defer stream_buffer.deinit();

            var decoder = Decoder{
                .slice = line[iterator.i..],
            };

            var glyph_buffer = GlyphBuffer{
                .codepoint = codepoint,
                .code = undefined,
                .offset = undefined,
                .advance = undefined,
            };

            try decoder.compileCommandSequence(
                &glyph_buffer.advance,
                stream_buffer.writer(),
            );

            glyph_buffer.code = try stream_buffer.toOwnedSlice();

            try list.append(glyph_buffer);
        }

        std.sort.sort(GlyphBuffer, list.items, {}, orderGlyphBuffer);

        var buffered_writer = std.io.bufferedWriter(dst_stream);
        const writer = buffered_writer.writer();

        try writer.writeIntLittle(u32, 0x4c2b8688);
        try writer.writeIntLittle(u32, @intCast(u32, list.items.len));

        var run_offset: u32 = 0;

        for (list.items) |glyph| {
            try writer.writeIntLittle(u32, @bitCast(u32, CodepointAdvancePair{
                .codepoint = glyph.codepoint,
                .advance = glyph.advance,
            }));
            try writer.writeIntLittle(u32, run_offset);

            run_offset += @intCast(u32, glyph.code.len);
        }

        for (list.items) |glyph| {
            try writer.writeAll(glyph.code);
        }

        try buffered_writer.flush();
    }
};

pub fn Rasterizer(
    comptime Context: type,
    comptime Color: type,
    comptime setPixel: fn (Context, x: i16, y: i16, Color) void,
) type {
    return struct {
        context: Context,

        pub fn render(raster: Rasterizer, x: i16, y: i16, string: []const u8, font: Font, color: Color) void {
            _ = x;
            _ = y;
            _ = raster;
            _ = string;
            _ = font;
            _ = color;
            _ = setPixel;
        }
    };
}

const Coordinate = packed struct {
    x: u4,
    y: u4,
};

const CodepointAdvancePair = packed struct(u32) {
    codepoint: u24,
    advance: u8,
};
