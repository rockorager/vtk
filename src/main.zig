const std = @import("std");
pub const vaxis = @import("vaxis");

pub const Button = @import("Button.zig");
pub const Spinner = @import("Spinner.zig");
pub const TextInput = @import("TextInput.zig");

pub const AppEvent = struct {
    kind: u16,
    event: *const anyopaque,
};

pub const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    focus_in, // window has gained focus
    focus_out, // window has lost focus
    paste_start, // bracketed paste start
    paste_end, // bracketed paste end
    paste: []const u8, // osc 52 paste, caller must free
    color_report: vaxis.Color.Report, // osc 4, 10, 11, 12 response
    color_scheme: vaxis.Color.Scheme, // light / dark OS theme changes
    winsize: vaxis.Winsize, // the window size has changed. This event is always sent when the loop is started
    app: AppEvent, // A custom event from the app
    redraw, // A generic redraw event
};

pub const EventLoop = vaxis.Loop(Event);

/// Application context, passed to the `update` function
pub const Context = struct {
    loop: *EventLoop,
    should_quit: *std.atomic.Value(bool),
    scheduled_events: *std.ArrayList(i64),

    // Tell the application to quit. Thread safe.
    pub fn quit(self: Context) void {
        self.should_quit.store(true, .unordered);
    }

    // Trigger a redraw event. Thread safe.
    pub fn redraw(self: Context) void {
        _ = self.loop.tryPostEvent(.redraw);
    }

    // Triggers a redraw event to be inserted into the queue on the next tick after timestamp_ms
    pub fn updateAt(self: Context, timestamp_ms: i64) std.mem.Allocator.Error!void {
        try self.scheduled_events.append(timestamp_ms);
        std.sort.insertion(i64, self.scheduled_events.items, {}, std.sort.desc(i64));
    }
};

pub const DrawContext = struct {
    arena: std.mem.Allocator,
    min: Size,

    pub fn withMinSize(self: DrawContext, min: Size) DrawContext {
        var new = self;
        new.min = min;
        return new;
    }
};

pub const Size = struct {
    width: usize = 0,
    height: usize = 0,

    // Resolves the size, preferring an odd number. Assumes, but does not assert, that wants is an odd
    // number. This means the result is only adjusted if it isn't the max or the min
    pub fn preferOdd(min: usize, max: usize, wants: usize) usize {
        const tgt = resolveConstraint(min, max, wants);
        // Already odd
        if (tgt % 2 != 0) return tgt;

        // At max, have room to shrink
        if (tgt == max and tgt > min) return tgt - 1;

        // At min, have room to grow
        if (tgt == min and tgt < max) return tgt + 1;

        return tgt;
    }
};

/// The Widget interface
pub const Widget = struct {
    userdata: *anyopaque,
    updateFn: *const fn (userdata: *anyopaque, ctx: Context, event: Event) anyerror!void,
    drawFn: *const fn (userdata: *anyopaque, ctx: DrawContext, win: vaxis.Window) anyerror!Size,
};

pub const RunOptions = struct {
    // Target frames / second
    framerate: u8 = 60,
};

pub fn run(allocator: std.mem.Allocator, widget: Widget, opts: RunOptions) anyerror!void {
    if (opts.framerate == 0) return error.InvalidFramerate;

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
    const tick: u64 = @divFloor(std.time.ns_per_s, @as(u64, opts.framerate));

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

    const draw_ctx: DrawContext = .{
        .arena = arena.allocator(),
        .min = .{ .width = 0, .height = 0 },
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
                .winsize => |ws| {
                    try vx.resize(allocator, buffered.writer().any(), ws);
                    try buffered.flush();
                },
                else => {},
            }
            should_draw = true;
            try widget.updateFn(widget.userdata, ctx, event);
        }

        if (should_quit.load(.unordered))
            return;

        if (should_draw) {
            defer _ = arena.reset(.retain_capacity);
            should_draw = false;
            const win = vx.window();
            win.clear();
            vx.setMouseShape(.default);
            _ = try widget.drawFn(widget.userdata, draw_ctx, win);

            try vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }
}

pub fn resolveConstraint(min: usize, max: usize, wants: usize) usize {
    std.debug.assert(min <= max);
    // 4 cases:
    // 1. no min, no pref => max
    // 2. max < wants => max
    // 3. min > wants => min
    // 4. wants
    if (wants == 0 and min == 0)
        return max
    else if (max < wants)
        return max
    else if (min > wants)
        return min
    else {
        std.debug.assert(wants >= min and wants <= max);
        return wants;
    }
}

test resolveConstraint {
    try std.testing.expectEqual(3, resolveConstraint(0, 10, 3));
}
