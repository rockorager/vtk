const std = @import("std");
pub const vaxis = @import("vaxis");

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
};

pub const EventLoop = vaxis.Loop(Event);

/// Application context, passed to the `update` function
pub const Context = struct {
    loop: *EventLoop,
    should_quit: *std.atomic.Value(bool),

    // Tell the application to quit. Thread safe.
    pub fn quit(self: *Context) void {
        self.should_quit.store(true, .unordered);
    }
};

/// The Widget interface
pub const Widget = struct {
    userdata: *anyopaque,
    updateFn: *const fn (userdata: *anyopaque, ctx: *Context, event: Event) anyerror!void,
    drawFn: *const fn (userdata: *anyopaque, arena: std.mem.Allocator, win: vaxis.Window) anyerror!void,
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

    // Calculate tick rate
    const tick: u64 = @divFloor(std.time.ns_per_s, @as(u64, opts.framerate));

    // Set up arena and context
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var buffered = tty.bufferedWriter();
    var has_event = false;
    var should_quit = std.atomic.Value(bool).init(false);

    var ctx: Context = .{
        .loop = &loop,
        .should_quit = &should_quit,
    };

    while (!should_quit.load(.unordered)) {
        // We handle drawing first to ensure a `quit` happens before a draw
        if (has_event) {
            defer _ = arena.reset(.retain_capacity);
            has_event = false;
            const win = vx.window();
            win.clear();
            vx.setMouseShape(.default);
            try widget.drawFn(widget.userdata, arena_alloc, win);

            try vx.render(buffered.writer().any());
            try buffered.flush();
        }

        std.time.sleep(tick);

        while (loop.tryEvent()) |event| {
            switch (event) {
                .winsize => |ws| {
                    try vx.resize(allocator, buffered.writer().any(), ws);
                    try buffered.flush();
                },
                else => {},
            }
            has_event = true;
            try widget.updateFn(widget.userdata, &ctx, event);
        }
    }
}
