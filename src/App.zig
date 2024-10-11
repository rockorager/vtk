const std = @import("std");
const vaxis = @import("vaxis");
const vtk = @import("main.zig");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

const Canvas = vtk.Canvas;
const EventLoop = vaxis.Loop(vtk.Event);
const Widget = vtk.Widget;

const App = @This();

quit_key: vaxis.Key = .{ .codepoint = 'c', .mods = .{ .ctrl = true } },

allocator: Allocator,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
event_loop: EventLoop,
timers: std.ArrayList(vtk.Tick),
redraw: bool = true,
quit: bool = false,

/// Runtime options
pub const Options = struct {
    framerate: u8 = 60,
};

/// Create an application. We require stable pointers to do the set up, so this will create an App
/// object on the heap. Call destroy when the app is complete to reset terminal state and release
/// resources
pub fn create(allocator: Allocator) !*App {
    const app = try allocator.create(App);

    app.* = .{
        .allocator = allocator,
        .tty = try vaxis.Tty.init(),
        .vx = try vaxis.init(allocator, .{ .system_clipboard_allocator = allocator }),
        .timers = std.ArrayList(vtk.Tick).init(allocator),

        // We init this after we have our stable pointers
        .event_loop = undefined,
    };

    app.event_loop = .{ .tty = &app.tty, .vaxis = &app.vx };
    try app.event_loop.init();
    app.event_loop.postEvent(.init);
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

    var mouse: ?vaxis.Mouse = null;

    while (true) {
        std.time.sleep(tick_ms * std.time.ns_per_ms);

        try self.checkTimers();

        while (self.event_loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(self.quit_key.codepoint, self.quit_key.mods)) {
                        self.quit = true;
                    }
                },
                .mouse => |m| mouse = m,
                .winsize => |ws| {
                    try vx.resize(self.allocator, buffered.writer().any(), ws);
                    try buffered.flush();
                    self.redraw = true;
                },
                else => {},
            }
            const maybe_cmd = widget.handleEvent(event);
            try self.handleCommand(maybe_cmd);
        }

        if (self.quit) return;
        if (!self.redraw) continue;
        self.redraw = false;

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
        if (mouse) |m| {
            var hits = std.ArrayList(vtk.HitResult).init(arena.allocator());
            defer hits.deinit();
            const sub: vtk.SubSurface = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = surface,
                .z_index = 0,
            };
            const mouse_point: vtk.Point = .{ .row = @intCast(m.row), .col = @intCast(m.col) };
            if (sub.containsPoint(mouse_point)) {
                try surface.hitTest(&hits, mouse_point);
            }
            while (hits.popOrNull()) |item| {
                var m_local = m;
                m_local.col = item.local.col;
                m_local.row = item.local.row;
                const maybe_cmd = item.widget.handleEvent(.{ .mouse = m_local });
                if (vtk.eventConsumed(maybe_cmd)) {
                    break;
                }
            }
        }
        surface.render(win);

        try vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

fn addTick(self: *App, tick: vtk.Tick) Allocator.Error!void {
    try self.timers.append(tick);
    std.sort.insertion(vtk.Tick, self.timers.items, {}, vtk.Tick.lessThan);
}

fn handleCommand(self: *App, maybe_cmd: ?vtk.Command) Allocator.Error!void {
    const cmd = maybe_cmd orelse return;
    switch (cmd) {
        .redraw => self.redraw = true,
        .tick => |tick| try self.addTick(tick),
        .consume_event => {}, // What do we do here?
        .batch => |cmds| {
            for (cmds) |c| {
                try self.handleCommand(c);
            }
        },
    }
}

fn checkTimers(self: *App) Allocator.Error!void {
    const now_ms = std.time.milliTimestamp();

    var expired = try std.ArrayList(vtk.Tick).initCapacity(self.allocator, self.timers.items.len);
    defer expired.deinit();

    // timers are always sorted descending
    var iter = std.mem.reverseIterator(self.timers.items);
    while (iter.next()) |tick| {
        if (now_ms < tick.deadline_ms)
            break;
        // Preallocated capacity
        expired.appendAssumeCapacity(tick);
        self.timers.items.len -= 1;
    }

    for (expired.items) |tick| {
        const maybe_cmd = tick.widget.handleEvent(.tick);
        try self.handleCommand(maybe_cmd);
    }
}
