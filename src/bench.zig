/// Throughput benchmark: feeds synthetic input through both implementations
/// in memory. Run with `zig run -OReleaseFast src/bench.zig` (add
/// `-mcpu x86_64_v3` for AVX2).
const std = @import("std");
const Io = std.Io;
const mojimod = @import("main.zig");

const input_size = 8 * 1024 * 1024;
const iterations = 5;

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const input = try buildInput(arena);
    const out_buf = try arena.alloc(u8, input.len + 64);

    const io = init.io;
    const ref_ns: u64 = @intCast(try bench(io, input, out_buf, runRef));
    const cur_ns: u64 = @intCast(try bench(io, input, out_buf, runCur));

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const out = &stdout_writer.interface;
    try out.print("input: {d} MiB x {d} iterations\n", .{ input_size / 1024 / 1024, iterations });
    try out.print("reference byte-machine: {d:>3} MiB/s\n", .{mibPerSec(ref_ns)});
    try out.print("current implementation: {d:>3} MiB/s\n", .{mibPerSec(cur_ns)});
    try out.print("speedup: {d:.2}x\n", .{@as(f64, @floatFromInt(ref_ns)) / @as(f64, @floatFromInt(cur_ns))});
    try out.flush();
}

fn mibPerSec(ns: u64) u64 {
    const total = @as(u64, input_size) * iterations;
    return total * std.time.ns_per_s / (ns * 1024 * 1024);
}

fn bench(io: std.Io, input: []const u8, out_buf: []u8, comptime run: fn ([]const u8, []u8) anyerror!usize) !i96 {
    var total: usize = 0;
    var sum: i96 = 0;
    for (0..iterations) |_| {
        const start = Io.Clock.awake.now(io).nanoseconds;
        const n = try run(input, out_buf);
        sum += Io.Clock.awake.now(io).nanoseconds - start;
        total += n;
    }
    std.mem.doNotOptimizeAway(total);
    return sum;
}

fn runRef(input: []const u8, out_buf: []u8) !usize {
    var reader = std.Io.Reader.fixed(input);
    var writer = Io.Writer.fixed(out_buf);
    try mojimod.refMojipath(&reader, &writer, false);
    return writer.buffered().len;
}

fn runCur(input: []const u8, out_buf: []u8) !usize {
    var reader = std.Io.Reader.fixed(input);
    var writer = Io.Writer.fixed(out_buf);
    try mojimod.mojipath(&reader, &writer, false);
    return writer.buffered().len;
}

fn buildInput(arena: std.mem.Allocator) ![]u8 {
    const input = try arena.alloc(u8, input_size);
    const line = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod\n";
    var i: usize = 0;
    var line_no: usize = 0;
    while (i < input.len) {
        if (line_no % 16 == 7) {
            const path = "/nix/store/m2yvkibsf6icc5csqjkm5ldbwgml7zs0-libmnl-1.0.5.drv\n";
            const n = @min(path.len, input.len - i);
            @memcpy(input[i..][0..n], path[0..n]);
            i += n;
        } else if (line_no % 16 == 11) {
            const near_miss = "prefix /nix/storeX suffix /nix/store abcdef 1234 end\n";
            const n = @min(near_miss.len, input.len - i);
            @memcpy(input[i..][0..n], near_miss[0..n]);
            i += n;
        } else {
            const n = @min(line.len, input.len - i);
            @memcpy(input[i..][0..n], line[0..n]);
            i += n;
        }
        line_no += 1;
    }
    return input;
}
