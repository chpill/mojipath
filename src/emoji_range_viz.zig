/// outputs emojis and there codepoint ranges, to help select "good-looking" ones
const std = @import("std");

pub fn main() void {
    for (0..70) |i| {
        std.debug.print("{x}-{x}:", .{ 0x1000 + i * 100, 0x1000 + (i + 1) * 100 });
        for (0..100) |j| {
            const codepoint: u21 = @intCast(0x1000 + i * 100 + j);
            std.debug.print("{u}", .{codepoint});
        }
        std.debug.print("\n", .{});
    }
}
