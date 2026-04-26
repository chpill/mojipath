const std = @import("std");
const Io = std.Io;

// Example of a nix store path:
// /nix/store/i0by19pwxrrc5i0w3zhs97xcc1x11va2-crate-wasm-bindgen-macro-0.2.92.tar.gz.drv
// pattern is 43 chars long:
// /nix/store/(32[0-9a-z])-

const path_prefix = "/nix/store/";
const path_hash_alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
const path_hash_len = 32;

// TODO: curate some "ranges" of cool emojis to use
const start_code_point = 0x2648;

pub fn mojipath(in: *Io.Reader, out: *Io.Writer) !void {
    var acc: [43]u8 = undefined;
    var acc_idx: [32]u21 = undefined;

    var j: u8 = 0;

    while (true) {
        const cs = in.take(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const c = cs[0];

        if (j == path_prefix.len + path_hash_len and c == '-') {
            const modifier = acc_idx[0] + acc_idx[1] + acc_idx[2] + acc_idx[3];
            const codepoint: u21 = start_code_point + modifier;
            try out.print("\u{2b21} {u}-", .{codepoint});
            j = 0;
            continue;
        }
        if (j < path_prefix.len) {
            if (c == path_prefix[j]) {
                acc[j] = c;
                j += 1;
                continue;
            } else {} // fall through to reset
        } else if (std.mem.find(u8, path_hash_alphabet, cs)) |found| {
            acc_idx[j - path_prefix.len] = @intCast(found);
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
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    var stdin_buffer: [1024]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;
    const stdout = &stdout_writer.interface;

    // TODO: error.WriteFailed should be unwrapped to surface the root problem?
    // https://ziggit.dev/t/file-i-o-basics-0-16/14968/4
    mojipath(stdin, stdout) catch |err| switch (err) {
        error.ReadFailed => return stdin_reader.err.?,
        error.WriteFailed => return stdout_writer.err.?,
        else => return err,
    };
    try stdout.flush();

    return 0;
}

fn check(input: []const u8, output: []const u8) !void {
    var reader = std.Io.Reader.fixed(input);
    var out_buf: [1024]u8 = undefined;
    var writer = Io.Writer.fixed(&out_buf);

    try mojipath(&reader, &writer);

    try std.testing.expectEqualStrings(output, writer.buffered());
}

test {
    try check(
        \\ /nix/store/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    ,
        \\ /nix/store/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    );

    try check(
        \\ /nix/store/m2yvkibsf6icc5csqjkm5ldbwgml7zs0-libmnl-1.0.5.drv
    ,
        \\ ⬡ ⚡-libmnl-1.0.5.drv
    );

    var u_buf: [4]u8 = undefined;
    const emoji_byte_size = try std.unicode.utf8Encode(0x2b21, &u_buf);
    try std.testing.expectEqualStrings("⬡", u_buf[0..emoji_byte_size]);
}
