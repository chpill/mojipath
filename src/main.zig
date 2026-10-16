const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

// Example of a nix store path:
// /nix/store/i0by19pwxrrc5i0w3zhs97xcc1x11va2-crate-wasm-bindgen-macro-0.2.92.tar.gz.drv
// pattern is 43 chars long:
// /nix/store/(32[0-9a-z])-

const path_prefix = "/nix/store/";
const path_hash_alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
const path_hash_len = 32;
const path_match_len = path_prefix.len + path_hash_len;
const match_unit_len = path_match_len + 1; // includes the trailing '-'

pub const window_size = 32768;

/// 32-byte vectors lower to real AVX2 ops only when the target enables it;
/// otherwise they split into 2x SSE2 ops, so keep 16 unless told otherwise.
const simd_width: comptime_int = if (builtin.cpu.has(.x86, .avx2)) 32 else 16;

// Monochrome symbols (text presentation by default) so the truecolor tint
// applies; colorful emoji glyphs are bitmaps and would ignore the color.
// Round-robin over these assigned, non-emoji-presentation blocks:
// 2300-23FF 25A0-25FF 2600-26FF 2700-27BF 2B00-2BFF 2190-21FF 27F0-27FF
// 2900-297F 16A0-16F9 2400-243F. Run `zig run src/emoji_range_viz.zig` to
// eyeball them. The hash maps uniformly onto any length.
pub const glyphs = [_]u21{
    0x2300, 0x25A0, 0x2600, 0x2700, 0x2B00, 0x2190, 0x27F0, 0x2900,
    0x16A0, 0x2400, 0x2301, 0x25A1, 0x2601, 0x2701, 0x2B01, 0x2191,
    0x27F1, 0x2901, 0x16A1, 0x2401, 0x2302, 0x25A2, 0x2602, 0x2702,
    0x2B02, 0x2192, 0x27F2, 0x2902, 0x16A2, 0x2402, 0x2303, 0x25A3,
    0x2603, 0x2703, 0x2B03, 0x2193, 0x27F3, 0x2903, 0x16A3, 0x2403,
    0x2304, 0x25A4, 0x2604, 0x2704, 0x2B04, 0x2194, 0x27F4, 0x2904,
    0x16A4, 0x2404, 0x2305, 0x25A5, 0x2605, 0x2B05, 0x2195, 0x27F5,
    0x2905, 0x16A5, 0x2405, 0x2306, 0x25A6, 0x2606, 0x2706, 0x2B06,
    0x2196, 0x27F6, 0x2906, 0x16A6, 0x2406, 0x2307, 0x25A7, 0x2607,
    0x2707, 0x2B07, 0x2197, 0x27F7, 0x2907, 0x16A7, 0x2407, 0x2308,
    0x25A8, 0x2608, 0x2708, 0x2B08, 0x2198, 0x27F8, 0x2908, 0x16A8,
    0x2408, 0x2309, 0x25A9, 0x2609, 0x2709, 0x2B09, 0x2199, 0x27F9,
    0x2909, 0x16A9, 0x2409, 0x230A, 0x25AA, 0x260A, 0x2B0A, 0x219A,
    0x27FA, 0x290A, 0x16AA, 0x240A, 0x230B, 0x25AB, 0x260B, 0x2B0B,
    0x219B, 0x27FB, 0x290B, 0x16AB, 0x240B, 0x230C, 0x25AC, 0x260C,
    0x270C, 0x2B0C, 0x219C, 0x27FC, 0x290C, 0x16AC, 0x240C, 0x230D,
    0x25AD, 0x260D, 0x270D, 0x2B0D, 0x219D, 0x27FD, 0x290D, 0x16AD,
    0x240D, 0x230E, 0x25AE, 0x260E, 0x270E, 0x2B0E, 0x219E, 0x27FE,
    0x290E, 0x16AE, 0x240E, 0x230F, 0x25AF, 0x260F, 0x270F, 0x2B0F,
    0x219F, 0x27FF, 0x290F, 0x16AF, 0x240F, 0x2310, 0x25B0, 0x2610,
    0x2710, 0x2B10, 0x21A0, 0x2910, 0x16B0, 0x2410, 0x2311, 0x25B1,
    0x2611, 0x2711, 0x2B11, 0x21A1, 0x2911, 0x16B1, 0x2411, 0x2312,
    0x25B2, 0x2612, 0x2712, 0x2B12, 0x21A2, 0x2912, 0x16B2, 0x2412,
    0x2313, 0x25B3, 0x2613, 0x2713, 0x2B13, 0x21A3, 0x2913, 0x16B3,
    0x2413, 0x2314, 0x25B4, 0x2714, 0x2B14, 0x21A4, 0x2914, 0x16B4,
    0x2414, 0x2315, 0x25B5, 0x2715, 0x2B15, 0x21A5, 0x2915, 0x16B5,
    0x2415, 0x2316, 0x25B6, 0x2616, 0x2716, 0x2B16, 0x21A6, 0x2916,
    0x16B6, 0x2416, 0x2317, 0x25B7, 0x2617, 0x2717, 0x2B17, 0x21A7,
    0x2917, 0x16B7, 0x2417, 0x2318, 0x25B8, 0x2618, 0x2718, 0x2B18,
    0x21A8, 0x2918, 0x16B8, 0x2418, 0x2319, 0x25B9, 0x2619, 0x2719,
    0x2B19, 0x21A9, 0x2919, 0x16B9, 0x2419, 0x25BA, 0x261A, 0x271A,
    0x2B1A, 0x21AA, 0x291A, 0x16BA, 0x241A, 0x25BB, 0x261B, 0x271B,
};

const glyph_saturation: f32 = 0.75;
const glyph_lightness: f32 = 0.5;

const Color = enum { auto, always, never };

/// Exact streaming reference: rewrites every occurrence of
/// `/nix/store/[0-9a-z]{32}-`, backtracking through partial matches on
/// mismatch so it finds occurrences the naive byte-machine missed (e.g.
/// after a stray '/'). The fuzz test asserts the windowed implementation
/// produces identical output.
pub fn refMojipath(in: *Io.Reader, out: *Io.Writer, color: bool) !void {
    var m = RefMachine{ .out = out, .color = color };
    while (true) {
        const cs = in.take(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        try m.feed(cs[0]);
    }
    try out.writeAll(m.acc[0..m.j]);
}

const RefMachine = struct {
    out: *Io.Writer,
    color: bool,
    acc: [path_match_len]u8 = undefined,
    j: usize = 0,

    fn matchesAt(this: *RefMachine, c: u8) bool {
        if (this.j < path_prefix.len) return c == path_prefix[this.j];
        return this.j < path_match_len and ((c -% '0') < 10 or (c -% 'a') < 26);
    }

    fn feed(this: *RefMachine, first: u8) !void {
        var queue: [4 * path_match_len]u8 = undefined;
        queue[0] = first;
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) {
            const cur = queue[head];
            head += 1;
            if (this.j == path_match_len and cur == '-') {
                try emitMatch(this.out, &this.acc, this.color);
                this.j = 0;
                continue;
            }
            if (this.matchesAt(cur)) {
                this.acc[this.j] = cur;
                this.j += 1;
                continue;
            }
            if (this.j == 0) {
                try this.writeByte(cur);
                continue;
            }
            // Mismatch at j > 0: drop acc[0], then re-examine acc[1..j] and
            // cur from the initial state.
            try this.writeByte(this.acc[0]);
            const j_old = this.j;
            const rest = queue[head..tail];
            const dst = queue[j_old..][0..rest.len];
            if (j_old <= head) {
                std.mem.copyForwards(u8, dst, rest);
            } else {
                std.mem.copyBackwards(u8, dst, rest);
            }
            if (j_old > 1) @memcpy(queue[0 .. j_old - 1], this.acc[1..j_old]);
            queue[j_old - 1] = cur;
            this.j = 0;
            head = 0;
            tail = j_old + rest.len;
        }
    }

    fn writeByte(this: *RefMachine, c: u8) !void {
        try this.out.writeAll(&.{c});
        if (c == '\n' or c == '\r') try this.out.flush();
    }
};

fn emitMatch(out: *Io.Writer, hash_and_prefix: []const u8, color: bool) !void {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(hash_and_prefix[path_prefix.len..]);
    const h = hasher.final();
    const glyph = glyphs[@intCast((h >> 32) % glyphs.len)];
    const hue: u32 = @intCast(h % 360);
    if (color) {
        const rgb = hslToRgb(hue, glyph_saturation, glyph_lightness);
        try out.print("\u{2b21} \x1b[38;2;{d};{d};{d}m{u}\x1b[0m-", .{ rgb.r, rgb.g, rgb.b, glyph });
    } else {
        try out.print("\u{2b21} {u}-", .{glyph});
    }
}

pub fn mojipath(in: *Io.Reader, out: *Io.Writer, color: bool) !void {
    var eof = false;
    while (true) {
        const window_cap = @min(window_size, in.buffer.len);
        while (!eof and in.bufferedLen() < window_cap) {
            in.fillMore() catch |e| switch (e) {
                error.EndOfStream => {
                    eof = true;
                    break;
                },
                else => return e,
            };
        }
        const window = in.buffered();
        if (window.len == 0) return;
        const consumed = try processWindow(window, out, color, eof);
        in.toss(consumed);
    }
}

/// Copies (or emits emojis for) everything it can decide about, leaving a
/// trailing potential partial match unconsumed so it can complete with more
/// input. At EOF the tail is flushed verbatim.
fn processWindow(window: []u8, out: *Io.Writer, color: bool, eof: bool) !usize {
    var emitted: usize = 0;
    var i: usize = 0;
    while (i < window.len) {
        const pos = i + (findSlash(window[i..]) orelse {
            try writeVerbatim(out, window[emitted..]);
            return window.len;
        });
        if (window.len - pos < match_unit_len) {
            if (eof) {
                try writeVerbatim(out, window[emitted..]);
                return window.len;
            }
            try writeVerbatim(out, window[emitted..pos]);
            return pos;
        }
        if (verifyStorePath(window[pos..][0..match_unit_len])) {
            try writeVerbatim(out, window[emitted..pos]);
            try emitMatch(out, window[pos..][0..path_match_len], color);
            emitted = pos + match_unit_len;
            i = pos + match_unit_len;
        } else {
            i = pos + 1;
        }
    }
    try writeVerbatim(out, window[emitted..]);
    return window.len;
}

fn writeVerbatim(out: *Io.Writer, bytes: []const u8) !void {
    try out.writeAll(bytes);
    if (hasLineBreak(bytes)) try out.flush();
}

fn hasLineBreak(bytes: []const u8) bool {
    const V = simd_width;
    const MaskInt = if (V == 32) u32 else u16;
    var i: usize = 0;
    while (i + V <= bytes.len) : (i += V) {
        const v: @Vector(V, u8) = bytes[i..][0..V].*;
        const nl: @Vector(V, bool) = v == @as(@Vector(V, u8), @splat('\n'));
        const cr: @Vector(V, bool) = v == @as(@Vector(V, u8), @splat('\r'));
        const mask: MaskInt = @bitCast(nl | cr);
        if (mask != 0) return true;
    }
    for (bytes[i..]) |c| {
        if (c == '\n' or c == '\r') return true;
    }
    return false;
}

fn findSlash(bytes: []const u8) ?usize {
    const V = simd_width;
    const MaskInt = if (V == 32) u32 else u16;
    var i: usize = 0;
    while (i + V <= bytes.len) : (i += V) {
        const v: @Vector(V, u8) = bytes[i..][0..V].*;
        const eq: @Vector(V, bool) = v == @as(@Vector(V, u8), @splat('/'));
        const mask: MaskInt = @bitCast(eq);
        if (mask != 0) return i + @ctz(mask);
    }
    return std.mem.indexOfScalarPos(u8, bytes, i, '/');
}

fn verifyStorePath(b: *const [match_unit_len]u8) bool {
    const prefix_padded = comptime blk: {
        var a: [16]u8 = @splat(0);
        @memcpy(a[0..path_prefix.len], path_prefix);
        break :blk a;
    };
    const v: @Vector(16, u8) = b[0..16].*;
    const eq: @Vector(16, bool) = v == prefix_padded;
    const prefix_mask: u16 = @bitCast(eq);
    // Lanes 11-15 must not match the zero padding; hash chars never can.
    if (prefix_mask != 0x07FF) return false;

    const h: @Vector(32, u8) = b[path_prefix.len..][0..32].*;
    const zeros: @Vector(32, u8) = @splat('0');
    const aas: @Vector(32, u8) = @splat('a');
    const digit: @Vector(32, bool) = (h -% zeros) < @as(@Vector(32, u8), @splat(10));
    const lower: @Vector(32, bool) = (h -% aas) < @as(@Vector(32, u8), @splat(26));
    if (!@reduce(.And, digit | lower)) return false;

    return b[path_match_len] == '-';
}

const Rgb = struct { r: u8, g: u8, b: u8 };

fn hslToRgb(hue: u32, sat: f32, light: f32) Rgb {
    const c = (1 - @abs(2 * light - 1)) * sat;
    const hp: f32 = @floatFromInt(hue % 360);
    const x = c * (1 - @abs(@mod(hp / 60, 2) - 1));
    const m = light - c / 2;
    const rgb: [3]f32 = switch (@as(u8, @intFromFloat(hp / 60))) {
        0 => .{ c, x, 0 },
        1 => .{ x, c, 0 },
        2 => .{ 0, c, x },
        3 => .{ 0, x, c },
        4 => .{ x, 0, c },
        else => .{ c, 0, x },
    };
    return .{
        .r = @intFromFloat((rgb[0] + m) * 255 + 0.5),
        .g = @intFromFloat((rgb[1] + m) * 255 + 0.5),
        .b = @intFromFloat((rgb[2] + m) * 255 + 0.5),
    };
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    var mode: Color = .auto;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--color=")) {
            mode = std.meta.stringToEnum(Color, arg["--color=".len..]) orelse {
                std.debug.print("unknown --color value: '{s}'\n", .{arg});
                return 2;
            };
        } else {
            std.debug.print("usage: mojipath [--color=auto|always|never]\n", .{});
            return 2;
        }
    }
    const color = switch (mode) {
        .always => true,
        .never => false,
        .auto => try std.Io.File.stdout().isTty(io),
    };

    var stdin_buffer: [2 * window_size]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;
    const stdout = &stdout_writer.interface;

    // TODO: error.WriteFailed should be unwrapped to surface the root problem?
    // https://ziggit.dev/t/file-i-o-basics-0-16/14968/4
    mojipath(stdin, stdout, color) catch |err| switch (err) {
        error.ReadFailed => return stdin_reader.err.?,
        error.WriteFailed => return stdout_writer.err.?,
        else => return err,
    };
    try stdout.flush();

    return 0;
}

fn check(input: []const u8, output: []const u8, color: bool) !void {
    var reader = std.Io.Reader.fixed(input);
    var out_buf: [window_size + 128]u8 = undefined;
    var writer = Io.Writer.fixed(&out_buf);

    try mojipath(&reader, &writer, color);

    try std.testing.expectEqualStrings(output, writer.buffered());
}

const RecordingWriter = struct {
    written: std.ArrayList(u8) = .empty,
    flushes: usize = 0,
    writer: Io.Writer,

    fn init(buffer: []u8) RecordingWriter {
        return .{ .writer = .{
            .buffer = buffer,
            .vtable = &.{ .drain = drain },
        } };
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const this: *RecordingWriter = @alignCast(@fieldParentPtr("writer", w));
        this.flushes += 1;
        this.append(w.buffered()) catch return error.WriteFailed;
        w.end = 0;
        var n = w.buffered().len;
        for (data[0 .. data.len - 1]) |slice| {
            this.append(slice) catch return error.WriteFailed;
            n += slice.len;
        }
        for (0..splat) |_| this.append(data[data.len - 1]) catch return error.WriteFailed;
        return n + splat * data[data.len - 1].len;
    }

    fn append(this: *RecordingWriter, bytes: []const u8) !void {
        try this.written.appendSlice(std.testing.allocator, bytes);
    }
};

test "flushes per line and per carriage return" {
    var buf: [1024]u8 = undefined;
    var rw = RecordingWriter.init(&buf);
    var reader = Io.Reader.fixed("abc\rdef\n");
    defer rw.written.deinit(std.testing.allocator);

    try mojipath(&reader, &rw.writer, false);

    // Newline bytes must trigger flushing; the exact count is an
    // implementation detail (batched writes flush once for several).
    try std.testing.expect(rw.flushes >= 1);
    try std.testing.expectEqualStrings("abc\rdef\n", rw.written.items);
}

test {
    try check(
        \\ /nix/store/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    ,
        \\ /nix/store/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    , false);

    const hash = "m2yvkibsf6icc5csqjkm5ldbwgml7zs0";
    try check(
        \\ /nix/store/m2yvkibsf6icc5csqjkm5ldbwgml7zs0-libmnl-1.0.5.drv
    ,
        \\ ⬡ ↧-libmnl-1.0.5.drv
    , false);

    try check(
        "/nix/store/" ++ hash ++ "-libmnl-1.0.5.drv\n",
        "\u{2b21} \x1b[38;2;32;35;223m\u{21a7}\x1b[0m-libmnl-1.0.5.drv\n",
        true,
    );

    // Input ending mid-match should be flushed verbatim, not dropped.
    try check(
        \\ /nix/store/m2yvkibsf6icc5csqjkm5ldbwgml7zs0
    ,
        \\ /nix/store/m2yvkibsf6icc5csqjkm5ldbwgml7zs0
    , false);

    var u_buf: [4]u8 = undefined;
    const emoji_byte_size = try std.unicode.utf8Encode(0x2b21, &u_buf);
    try std.testing.expectEqualStrings("⬡", u_buf[0..emoji_byte_size]);
}

test "match straddling the window boundary at every offset" {
    const hash = "m2yvkibsf6icc5csqjkm5ldbwgml7zs0";
    const path_line = "/nix/store/" ++ hash ++ "-n\n";
    var expected_buf: [window_size + 64]u8 = undefined;
    var input_buf: [window_size + 128]u8 = undefined;

    var offset: usize = 0;
    while (offset <= match_unit_len) : (offset += 1) {
        const filler_len = window_size - offset;
        @memset(input_buf[0..filler_len], 'a');
        @memcpy(input_buf[filler_len..][0..path_line.len], path_line);
        const input = input_buf[0 .. filler_len + path_line.len];

        @memset(expected_buf[0..filler_len], 'a');
        const emoji = "⬡ ↧";
        @memcpy(expected_buf[filler_len..][0..emoji.len], emoji);
        const tail = "-n\n";
        @memcpy(expected_buf[filler_len + emoji.len ..][0..tail.len], tail);
        const expected = expected_buf[0 .. filler_len + emoji.len + tail.len];

        try check(input, expected, false);
    }
}

test "fuzz: windowed output matches reference implementation" {
    var prng = std.Random.DefaultPrng.init(0xfeedface);
    const rand = prng.random();

    var iter: usize = 0;
    while (iter < 500) : (iter += 1) {
        const len = rand.uintLessThan(usize, 8192);
        const input = try std.testing.allocator.alloc(u8, len);
        defer std.testing.allocator.free(input);

        const noise = "lorem ipsum dolor sit amet\nconsectetur /nix/storeX adi/pi scing\r";
        for (input) |*c| {
            c.* = noise[rand.uintLessThan(usize, noise.len)];
        }
        // Embed full paths and near-misses at random positions.
        const hash = "m2yvkibsf6icc5csqjkm5ldbwgml7zs0";
        const full = "/nix/store/" ++ hash ++ "-libmnl-1.0.5";
        const near_miss_1 = "/nix/store" ++ hash; // missing slash
        const near_miss_2 = "/nix/store/abc-def-"; // short hash
        const near_miss_3 = "/nix/store/" ++ hash[0..31]; // no trailing dash
        const snippets = [_][]const u8{ full, near_miss_1, near_miss_2, near_miss_3 };
        const snip = snippets[rand.uintLessThan(usize, snippets.len)];
        if (len > snip.len) {
            const at = rand.uintLessThan(usize, len - snip.len);
            @memcpy(input[at..][0..snip.len], snip);
        }

        var a = std.Io.Reader.fixed(input);
        var a_buf: [2 * 8192]u8 = undefined;
        var aw = Io.Writer.fixed(&a_buf);
        var b = std.Io.Reader.fixed(input);
        var b_buf: [2 * 8192]u8 = undefined;
        var bw = Io.Writer.fixed(&b_buf);

        try mojipath(&a, &aw, iter % 2 == 0);
        try refMojipath(&b, &bw, iter % 2 == 0);

        try std.testing.expectEqualStrings(bw.buffered(), aw.buffered());
    }
}
