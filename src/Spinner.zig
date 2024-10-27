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

test Spinner {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Create a spinner
    var spinner: Spinner = .{};
    // Get our widget interface
    const spinner_widget = spinner.widget();

    // Start the spinner. This (maybe) returns a Tick command to schedule the next frame. If the
    // spinner is already running, no command is returned. Calling start is thread safe
    const maybe_cmd = spinner.start();
    try std.testing.expect(maybe_cmd != null);
    try std.testing.expect(maybe_cmd.? == .tick);
    try std.testing.expectEqual(1, spinner.count.load(.unordered));

    // If we call start again, we won't get another command but our counter will go up
    const maybe_cmd2 = spinner.start();
    try std.testing.expect(maybe_cmd2 == null);
    try std.testing.expectEqual(2, spinner.count.load(.unordered));

    // The event loop handles the tick event and calls us back with a .tick event. If we should keep
    // running, we will return a new tick event
    _ = try spinner_widget.handleEvent(.tick);

    // Receiving a .tick advances the frame
    try std.testing.expectEqual(1, spinner.frame);

    // Simulate a draw
    const surface = try spinner_widget.draw(.{ .arena = arena.allocator(), .min = .{}, .max = .{} });

    // Spinner will try to be 1x1
    try std.testing.expectEqual(1, surface.size.width);
    try std.testing.expectEqual(1, surface.size.height);

    // Stopping the spinner decrements our counter
    spinner.stop();
    try std.testing.expectEqual(1, spinner.count.load(.unordered));
    spinner.stop();
    try std.testing.expectEqual(0, spinner.count.load(.unordered));
}
