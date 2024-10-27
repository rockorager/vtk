const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Allocator = std.mem.Allocator;

const Spinner = @This();

const frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
const time_lapse: u32 = std.time.ms_per_s / 12; // 12 fps

count: std.atomic.Value(u16) = .{ .raw = 0 },
style: vaxis.Style = .{},
/// The frame index
frame: u4 = 0,
/// When we rearm the timer, we return a Tick and a redraw command. We statically allocate these up
/// front so we don't need an allocator
rearm: [2]vtk.Command = [_]vtk.Command{ .redraw, .redraw },

/// Start, or add one, to the spinner counter. Thread safe.
pub fn start(self: *Spinner) ?vtk.Command {
    const count = self.count.fetchAdd(1, .monotonic);
    if (count == 0) {
        return vtk.Tick.in(time_lapse, self.widget());
    }
    return null;
}

/// Reduce one from the spinner counter. The spinner will stop when it reaches 0. Thread safe
pub fn stop(self: *Spinner) void {
    self.count.store(self.count.load(.unordered) -| 1, .unordered);
}

pub fn widget(self: *Spinner) vtk.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) anyerror!?vtk.Command {
    const self: *Spinner = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

pub fn handleEvent(self: *Spinner, event: vtk.Event) ?vtk.Command {
    switch (event) {
        .tick => {
            const count = self.count.load(.unordered);

            if (count == 0) return null;
            // Update frame
            self.frame += 1;
            if (self.frame >= frames.len) self.frame = 0;

            // Update rearm
            self.rearm[0] = vtk.Tick.in(time_lapse, self.widget());
            return .{ .batch = &self.rearm };
        },
        else => return null,
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *Spinner = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *Spinner, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const size: vtk.Size = .{
        .width = @max(1, ctx.min.width),
        .height = @max(1, ctx.min.height),
    };

    const surface = try vtk.Surface.init(ctx.arena, self.widget(), size);
    @memset(surface.buffer, .{ .style = self.style });

    if (self.count.load(.unordered) == 0) return surface;

    surface.writeCell(0, 0, .{
        .char = .{
            .grapheme = frames[self.frame],
            .width = 1,
        },
        .style = self.style,
    });
    return surface;
}

test "Spinner satisfies widget interface" {
    var spinner: Spinner = .{};
    _ = spinner.widget();
}
