const std = @import("std");
const vaxis = @import("vaxis");

pub const blue = colorFromHex("#7aa2f7");
pub const dark_blue = colorFromHex("#3d59a1");

fn colorFromHex(comptime hex: []const u8) vaxis.Color {
    if (hex.len != 7) @compileError("invalid hex color");
    const val = std.fmt.parseUnsigned(u24, hex[1..], 16) catch unreachable;
    return vaxis.Color.rgbFromUint(val);
}
