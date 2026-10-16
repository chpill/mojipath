/// Throughput benchmark: feeds synthetic input through both implementations
/// in memory. Run with `zig run -OReleaseFast src/bench.zig` (add
/// `-mcpu x86_64_v3` for AVX2). Alternates measurements and reports medians
/// to cancel frequency-scaling drift.
const std = @import("std");
const Io = std.Io;
const mojimod = @import("main.zig");

const input_size = 8 * 1024 * 1024;
const rounds = 9;

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const input = try buildInput(arena);
    const out_buf = try arena.alloc(u8, input.len + 64);

    const io = init.io;
    var ceil_samples: [rounds]i96 = undefined;
    var ref_samples: [rounds]i96 = undefined;
    var cur_samples: [rounds]i96 = undefined;
    for (0..rounds) |r| {
        ceil_samples[r] = try benchOne(io, input, out_buf, runCeiling);
        ref_samples[r] = try benchOne(io, input, out_buf, runRef);
        cur_samples[r] = try benchOne(io, input, out_buf, runCur);
    }

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout_writer.interface;
    try out.print("input: {d} MiB, median of {d} interleaved rounds\n", .{ input_size / 1024 / 1024, rounds });
    try out.print("memcpy ceiling:         {d:>6} MiB/s\n", .{mibPerSec(median(&ceil_samples))});
    try out.print("reference byte-machine: {d:>6} MiB/s\n", .{mibPerSec(median(&ref_samples))});
    try out.print("current implementation: {d:>6} MiB/s\n", .{mibPerSec(median(&cur_samples))});
    try out.print("ratio impl/ceiling: {d:.2}\n", .{
        @as(f64, @floatFromInt(median(&ceil_samples))) / @as(f64, @floatFromInt(median(&cur_samples))),
    });
    try out.flush();
}

fn median(samples: []i96) i96 {
    std.mem.sort(i96, samples, {}, std.sort.asc(i96));
    return samples[samples.len / 2];
}

fn mibPerSec(ns: i96) u64 {
    const total: i96 = input_size;
    return @intCast(@divTrunc(total * std.time.ns_per_s, ns * 1024 * 1024));
}

fn benchOne(io: std.Io, input: []const u8, out_buf: []u8, comptime run: fn ([]const u8, []u8) anyerror!usize) !i96 {
    var checksum: usize = 0;
    const start = Io.Clock.awake.now(io).nanoseconds;
    checksum += try run(input, out_buf);
    checksum += try run(input, out_buf);
    checksum += try run(input, out_buf);
    const elapsed = Io.Clock.awake.now(io).nanoseconds - start;
    std.mem.doNotOptimizeAway(checksum);
    return @divTrunc(elapsed, 3);
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

fn runCeiling(input: []const u8, out_buf: []u8) !usize {
    var writer = Io.Writer.fixed(out_buf);
    var i: usize = 0;
    while (i < input.len) : (i += mojimod.window_size) {
        try writer.writeAll(input[i..@min(i + mojimod.window_size, input.len)]);
    }
    return input.len;
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
