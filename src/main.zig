const std = @import("std");
const Io = std.Io;

// Example of a nix store path:
// /nix/store/i0by19pwxrrc5i0w3zhs97xcc1x11va2-crate-wasm-bindgen-macro-0.2.92.tar.gz.drv
// pattern is 43 chars long:
// /nix/store/(32[0-9a-z])-

const path_prefix = "/nix/store/";
const path_hash_alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
const path_hash_len = 32;
const path_match_len = path_prefix.len + path_hash_len;

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

pub fn mojipath(in: *Io.Reader, out: *Io.Writer, color: bool) !void {
    var acc: [path_match_len]u8 = undefined;

    var j: u8 = 0;

    while (true) {
        const cs = in.take(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const c = cs[0];

        if (j == path_match_len and c == '-') {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(acc[path_prefix.len..]);
            const h = hasher.final();
            const glyph = glyphs[@intCast((h >> 32) % glyphs.len)];
            const hue: u32 = @intCast(h % 360);
            if (color) {
                const rgb = hslToRgb(hue, glyph_saturation, glyph_lightness);
                try out.print("\u{2b21} \x1b[38;2;{d};{d};{d}m{u}\x1b[0m-", .{ rgb.r, rgb.g, rgb.b, glyph });
            } else {
                try out.print("\u{2b21} {u}-", .{glyph});
            }
            j = 0;
            continue;
        }
        if (j < path_prefix.len) {
            if (c == path_prefix[j]) {
                acc[j] = c;
                j += 1;
                continue;
            }
        } else if (std.mem.find(u8, path_hash_alphabet, cs)) |found| {
            acc[j] = path_hash_alphabet[found];
            j += 1;
            continue;
        }

        // If the control flow reaches here, there is no match, reset everything
        try out.writeAll(acc[0..j]);
        try out.writeAll(cs);
        if (c == '\n') try out.flush();
        j = 0;
    }
    try out.writeAll(acc[0..j]);
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

    var stdin_buffer: [1024]u8 = undefined;
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
    var out_buf: [1024]u8 = undefined;
    var writer = Io.Writer.fixed(&out_buf);

    try mojipath(&reader, &writer, color);

    try std.testing.expectEqualStrings(output, writer.buffered());
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
