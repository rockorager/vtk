const std = @import("std");
const vaxis = @import("vaxis");
const vtk = @import("main.zig");

pub fn createDrawContext(
    allocator: std.mem.Allocator,
    w: u16,
    h: u16,
) !vtk.DrawContext {
    const unicode = try allocator.create(vaxis.Unicode);
    unicode.* = try vaxis.Unicode.init(allocator);

    return .{
        .arena = allocator,
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = w, .height = h },
        .unicode = unicode,
        .width_method = .unicode,
    };
}

pub fn destroyDrawContext(ctx: vtk.DrawContext) void {
    ctx.unicode.deinit();
    ctx.arena.destroy(ctx.unicode);
}

test {
    _ = @import("main.zig");
    _ = @import("Text.zig");
}
