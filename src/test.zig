const std = @import("std");
const vaxis = @import("vaxis");

pub fn createWindow(allocator: std.mem.Allocator, w: usize, h: usize) !vaxis.Window {
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
        .x_off = 0,
        .y_off = 0,
        .width = screen.width,
        .height = screen.height,
        .screen = screen,
    };
}

pub fn destroyWindow(allocator: std.mem.Allocator, window: vaxis.Window) void {
    window.screen.unicode.deinit();
    allocator.destroy(window.screen.unicode);
    window.screen.deinit(allocator);
    allocator.destroy(window.screen);
}

test {
    _ = @import("main.zig");
    _ = @import("TextInput.zig");
}
