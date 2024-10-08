// const std = @import("std");
// const vaxis = @import("vaxis");
//
// const vtk = @import("main.zig");
//
// const Spinner = @This();
//
// const frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
// const time_lapse: i64 = std.time.ms_per_s / 12; // 12 fps
//
// count: u16 = 0,
// mutex: std.Thread.Mutex = .{},
// style: vaxis.Style = .{},
// frame: u4 = 0,
// last_frame_ts: i64 = 0,
//
// pub fn start(self: *Spinner) void {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//     self.count +|= 1;
// }
//
// pub fn stop(self: *Spinner) void {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//     self.count -|= 1;
// }
//
// pub fn widget(self: *Spinner) vtk.Widget {
//     return .{
//         .userdata = self,
//         .updateFn = Spinner.update,
//         .drawFn = Spinner.draw,
//     };
// }
//
// pub fn updateErased(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
//     const self: *Spinner = @ptrCast(@alignCast(ptr));
//     return self.update(ctx, event);
// }
//
// pub fn update(self: *Spinner, ctx: vtk.Context, _: vtk.Event) anyerror!void {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//     if (self.count == 0) return;
//     const now = std.time.milliTimestamp();
//     if (self.last_frame_ts + time_lapse <= now) {
//         self.last_frame_ts = now;
//         try ctx.updateAt(now + time_lapse);
//         self.frame += 1;
//         if (self.frame >= frames.len) self.frame = 0;
//     }
// }
//
// pub fn drawErased(ptr: *anyopaque, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
//     const self: *Spinner = @ptrCast(@alignCast(ptr));
//     return self.draw(ctx, win);
// }
//
// pub fn draw(self: *Spinner, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//     const width = vtk.Size.preferOdd(ctx.min.width, win.width, 1);
//     const height = vtk.Size.preferOdd(ctx.min.height, win.height, 1);
//     const widget_win = win.child(.{
//         .width = .{ .limit = width },
//         .height = .{ .limit = height },
//     });
//     widget_win.fill(.{ .style = self.style });
//     if (self.count == 0) return .{ .width = width, .height = height };
//     const x = width / 2;
//     const y = height / 2;
//     win.writeCell(x, y, .{
//         .char = .{
//             .grapheme = frames[self.frame],
//             .width = 1,
//         },
//         .style = self.style,
//     });
//     return .{ .width = width, .height = height };
// }
