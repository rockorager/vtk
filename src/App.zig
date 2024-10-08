const std = @import("std");
const vaxis = @import("vaxis");
const vtk = @import("main.zig");

const Canvas = vtk.Canvas;
const Context = vtk.Context;
const EventLoop = vtk.EventLoop;
const Widget = vtk.Widget;

const App = @This();

/// The root widget
root: Widget,

framerate: u8 = 60,
quit_key: vaxis.Key = .{ .codepoint = 'c', .mods = .{ .ctrl = true } },

pub fn run(self: *App, allocator: std.mem.Allocator) anyerror!void {
    if (self.framerate == 0) return error.InvalidFramerate;

    // Initialize vaxis
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.anyWriter());

    var loop: EventLoop = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);
    // HACK: Ghostty is reporting incorrect pixel screen size
    vx.caps.sgr_pixels = false;
    try vx.setMouseMode(tty.anyWriter(), true);

    // Calculate tick rate
    const tick: u64 = @divFloor(std.time.ns_per_s, @as(u64, self.framerate));

    // Set up arena and context
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var buffered = tty.bufferedWriter();
    var should_draw = false;
    var should_quit = std.atomic.Value(bool).init(false);
    var scheduled_events = std.ArrayList(i64).init(allocator);
    defer scheduled_events.deinit();

    const ctx: Context = .{
        .loop = &loop,
        .should_quit = &should_quit,
        .scheduled_events = &scheduled_events,
    };

    while (true) {
        std.time.sleep(tick);

        const now = std.time.milliTimestamp();
        // scheduled_events are always sorted descending
        var iter = std.mem.reverseIterator(scheduled_events.items);
        var did_schedule = false;
        while (iter.next()) |ts| {
            if (now < ts)
                break;
            if (!did_schedule) {
                did_schedule = true;
                _ = loop.tryPostEvent(.redraw);
            }
            _ = scheduled_events.pop();
        }

        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(self.quit_key.codepoint, self.quit_key.mods)) {
                        _ = loop.tryPostEvent(.quit);
                    }
                },
                .winsize => |ws| {
                    try vx.resize(allocator, buffered.writer().any(), ws);
                    try buffered.flush();
                },
                .quit => should_quit.store(true, .unordered),
                .abort_quit => should_quit.store(false, .unordered),
                else => {},
            }
            should_draw = true;
            try self.root.eventHandler(self.root.userdata, ctx, event);
        }

        if (should_quit.load(.unordered))
            return;

        if (should_draw) {
            const canvas: Canvas = .{
                .arena = arena.allocator(),
                .screen = &vx.screen,
                .x_off = 0,
                .y_off = 0,
                .min = .{ .width = 0, .height = 0 },
                .max = .{
                    .width = @intCast(vx.screen.width),
                    .height = @intCast(vx.screen.height),
                },
            };
            defer _ = arena.reset(.retain_capacity);
            should_draw = false;
            const win = vx.window();
            win.clear();
            vx.setMouseShape(.default);
            _ = try self.root.drawFn(self.root.userdata, canvas);

            try vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }
}
