const std = @import("std");
const vaxis = @import("vaxis");
const vtk = @import("main.zig");

pub fn createCanvas(allocator: std.mem.Allocator, w: u16, h: u16) !vtk.Canvas {
    const unicode = try allocator.create(vaxis.Unicode);
    unicode.* = try vaxis.Unicode.init(allocator);

    const screen = try allocator.create(vaxis.Screen);
    const winsize: vaxis.Winsize = .{
        .cols = w,
        .rows = h,
        .x_pixel = 0,
        .y_pixel = 0,
    };
    screen.* = try vaxis.Screen.init(allocator, winsize, unicode);

    return .{
        .arena = allocator,
        .x_off = 0,
        .y_off = 0,
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = w, .height = h },
        .screen = screen,
    };
}

pub fn destroyCanvas(allocator: std.mem.Allocator, canvas: vtk.Canvas) void {
    canvas.screen.unicode.deinit();
    allocator.destroy(canvas.screen.unicode);
    canvas.screen.deinit(allocator);
    allocator.destroy(canvas.screen);
}

test {
    _ = @import("main.zig");

    _ = @import("Text.zig");
}
