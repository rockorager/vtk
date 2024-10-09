const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Spinner = @This();

const frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
const time_lapse: i64 = std.time.ms_per_s / 12; // 12 fps

count: std.atomic.Value(u16) = .{ .raw = 0 },
mutex: std.Thread.Mutex = .{},
style: vaxis.Style = .{},
frame: u4 = 0,

pub fn start(self: *Spinner, ctx: vtk.Context) void {
    const count = self.count.fetchAdd(1, .monotonic);
    if (count == 0) {
        const now = std.time.milliTimestamp();
        ctx.scheduleCallback(.{
            .deadline_ms = now + time_lapse,
            .ptr = self,
            .callback = callback,
        });
    }
}

fn callback(ptr: *anyopaque, ctx: vtk.Context) void {
    const self: *Spinner = @ptrCast(@alignCast(ptr));
    const count = self.count.load(.unordered);

    if (count == 0) return;
    // Update frame
    self.frame += 1;
    if (self.frame >= frames.len) self.frame = 0;

    // Reschedule callback
    const now = std.time.milliTimestamp();
    ctx.scheduleCallback(.{
        .deadline_ms = now + time_lapse,
        .ptr = self,
        .callback = callback,
    });
    ctx.postEvent(.redraw);
}

pub fn stop(self: *Spinner) void {
    self.count.store(self.count.load(.unordered) -| 1, .unordered);
}

pub fn widget(self: *Spinner) vtk.Widget {
    return .{
        .userdata = self,
        .eventHandler = vtk.noopEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *Spinner = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn draw(self: *Spinner, canvas: vtk.Canvas) anyerror!vtk.Size {
    const size: vtk.Size = .{
        .width = @max(1, canvas.min.width),
        .height = @max(1, canvas.min.height),
    };
    canvas.fillStyle(self.style, size);

    if (self.count.load(.unordered) == 0) return size;

    canvas.writeCell(0, 0, .{
        .char = .{
            .grapheme = frames[self.frame],
            .width = 1,
        },
        .style = self.style,
    });
    return size;
}
