const std = @import("std");
const vaxis = @import("vaxis");
const vtk = @import("main.zig");

const assert = std.debug.assert;

const Canvas = vtk.Canvas;
const Context = vtk.Context;
const EventLoop = vtk.EventLoop;
const Widget = vtk.Widget;

const App = @This();

quit_key: vaxis.Key = .{ .codepoint = 'c', .mods = .{ .ctrl = true } },

allocator: std.mem.Allocator,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
event_loop: EventLoop,
should_quit: std.atomic.Value(bool),
timers: std.ArrayList(vtk.Callback),

/// Runtime options
pub const Options = struct {
    framerate: u8 = 60,
};

/// Create an application. We require stable pointers to do the set up, so this will create an App
/// object on the heap. Call destroy when the app is complete to reset terminal state and release
/// resources
pub fn create(allocator: std.mem.Allocator) !*App {
    const app = try allocator.create(App);

    app.* = .{
        .allocator = allocator,
        .tty = try vaxis.Tty.init(),
        .vx = try vaxis.init(allocator, .{ .system_clipboard_allocator = allocator }),
        .should_quit = std.atomic.Value(bool).init(false),
        .timers = std.ArrayList(vtk.Callback).init(allocator),

        // We init this after we have our stable pointers
        .event_loop = undefined,
    };

    app.event_loop = .{ .tty = &app.tty, .vaxis = &app.vx };
    try app.event_loop.init();
    try app.event_loop.start();
    return app;
}

pub fn destroy(self: *App) void {
    self.event_loop.stop();
    self.timers.deinit();
    self.vx.deinit(self.allocator, self.tty.anyWriter());
    self.tty.deinit();
    self.allocator.destroy(self);
}

pub fn context(self: *App) vtk.Context {
    return .{
        .loop = &self.event_loop,
        .should_quit = &self.should_quit,
        .timers = &self.timers,
    };
}

pub fn run(self: *App, widget: vtk.Widget, opts: Options) anyerror!void {
    // Initialize vaxis
    const vx = &self.vx;
    const tty = &self.tty;

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);
    // HACK: Ghostty is reporting incorrect pixel screen size
    vx.caps.sgr_pixels = false;
    try vx.setMouseMode(tty.anyWriter(), true);

    const framerate: u64 = if (opts.framerate > 0) opts.framerate else 60;
    // Calculate tick rate
    const tick_ms: u64 = @divFloor(std.time.ms_per_s, framerate);

    // Set up arena and context
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    var buffered = tty.bufferedWriter();

    const ctx = self.context();

    while (true) {
        std.time.sleep(tick_ms * std.time.ns_per_ms);

        self.checkTimers();

        var should_draw = false;
        while (self.event_loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(self.quit_key.codepoint, self.quit_key.mods)) {
                        ctx.postEvent(.quit);
                    }
                },
                .winsize => |ws| {
                    try vx.resize(self.allocator, buffered.writer().any(), ws);
                    try buffered.flush();
                },
                .quit => self.should_quit.store(true, .unordered),
                .abort_quit => self.should_quit.store(false, .unordered),
                else => {},
            }
            should_draw = true;
            try widget.handleEvent(ctx, event);
        }

        if (!should_draw) continue;

        if (self.should_quit.load(.unordered))
            return;

        defer _ = arena.reset(.retain_capacity);

        const draw_context: vtk.DrawContext = .{
            .arena = arena.allocator(),
            .min = .{ .width = 0, .height = 0 },
            .max = .{
                .width = @intCast(vx.screen.width),
                .height = @intCast(vx.screen.height),
            },
            .unicode = &vx.unicode,
            .width_method = vx.screen.width_method,
        };
        const win = vx.window();
        win.clear();
        vx.setMouseShape(.default);
        const surface = try widget.draw(draw_context);
        surface.render(win);

        try vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

pub fn checkTimers(self: *App) void {
    const now_ms = std.time.milliTimestamp();
    const ctx = self.context();

    // timers are always sorted descending
    var iter = std.mem.reverseIterator(self.timers.items);
    while (iter.next()) |callback| {
        if (now_ms < callback.deadline_ms)
            break;
        callback.callback(callback.ptr, ctx);
        _ = self.timers.pop();
    }
}
