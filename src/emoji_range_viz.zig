/// Prints the glyph palette, to eyeball font coverage in a terminal.
const std = @import("std");
const mojipath = @import("main.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buffer);
    const out = &stdout_writer.interface;

    for (mojipath.glyphs, 0..) |cp, i| {
        try out.print("{d: >3} {u}   ", .{ i, cp });
        if ((i + 1) % 8 == 0) try out.writeByte('\n');
    }
    try out.writeByte('\n');
    try out.flush();
}
