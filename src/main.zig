const std = @import("std");
pub const vaxis = @import("vaxis");

const grapheme = vaxis.grapheme;

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

pub const App = @import("App.zig");
pub const Button = @import("Button.zig");
pub const Center = @import("Center.zig");
pub const FlexColumn = @import("FlexColumn.zig");
pub const FlexRow = @import("FlexRow.zig");
pub const Padding = @import("Padding.zig");
pub const Text = @import("Text.zig");
pub const Spinner = @import("Spinner.zig");

const log = std.log.scoped(.vtk);

pub const AppEvent = struct {
    kind: u16,
    event: ?*const anyopaque = null,
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
    quit, // The application will exit when the event loop is drained
    abort_quit, // Abort a quit event. This must be sent in response to a quit event to work
};

pub const EventLoop = vaxis.Loop(Event);

pub const Callback = struct {
    deadline_ms: i64,
    ptr: *anyopaque,
    callback: *const fn (*anyopaque, ctx: Context) void,

    pub fn lessThan(_: void, lhs: Callback, rhs: Callback) bool {
        return lhs.deadline_ms > rhs.deadline_ms;
    }
};

/// Application context, passed to the `eventHandler` function
pub const Context = struct {
    loop: *EventLoop,
    should_quit: *std.atomic.Value(bool),
    timers: *std.ArrayList(Callback),

    // Tell the application to quit. Thread safe.
    pub fn quit(self: Context) void {
        self.should_quit.store(true, .unordered);
    }

    pub fn scheduleCallback(self: Context, callback: Callback) void {
        self.timers.append(callback) catch return;
        std.sort.insertion(Callback, self.timers.items, {}, Callback.lessThan);
    }

    pub fn postEvent(self: Context, event: Event) void {
        // Use try post to prevent a deadlock if this is called from the main thread
        const success = self.loop.tryPostEvent(event);
        if (!success) log.warn("event dropped: {}", .{event});
    }
};

pub const DrawContext = struct {
    // Allocator backed by an arena. Widgets do not need to free their own resources, they will be
    // freed after rendering
    arena: std.mem.Allocator,
    // Constraints
    min: Size,
    max: Size,

    // Unicode stuff
    unicode: *const vaxis.Unicode,
    width_method: vaxis.gwidth.Method,

    pub fn stringWidth(self: DrawContext, str: []const u8) usize {
        return vaxis.gwidth.gwidth(
            str,
            self.width_method,
            self.unicode.width_data,
        );
    }

    pub fn graphemeIterator(self: DrawContext, str: []const u8) grapheme.Iterator {
        return self.unicode.graphemeIterator(str);
    }

    pub fn withContstraints(self: DrawContext, min: Size, max: Size) DrawContext {
        return .{
            .arena = self.arena,
            .min = min,
            .max = max,
            .unicode = self.unicode,
            .width_method = self.width_method,
        };
    }

    pub fn withContraintsAndAllocator(
        self: DrawContext,
        min: Size,
        max: Size,
        arena: Allocator,
    ) DrawContext {
        return .{
            .arena = arena,
            .min = min,
            .max = max,
            .unicode = self.unicode,
            .width_method = self.width_method,
        };
    }
};

pub const Size = struct {
    width: u16 = 0,
    height: u16 = 0,

    // Resolves the size, preferring an odd number. Assumes, but does not assert, that wants is an odd
    // number. This means the result is only adjusted if it isn't the max or the min
    pub fn preferOdd(min: u16, max: u16, wants: u16) u16 {
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
    eventHandler: *const fn (userdata: *anyopaque, ctx: Context, event: Event) anyerror!void,
    drawFn: *const fn (userdata: *anyopaque, canvas: Canvas) anyerror!Size,

    pub fn handleEvent(self: Widget, ctx: Context, event: Event) anyerror!void {
        return self.eventHandler(self.userdata, ctx, event);
    }

    pub fn draw(self: Widget, canvas: Canvas) anyerror!Size {
        return self.drawFn(self.userdata, canvas);
    }
};

pub const FlexItem = struct {
    widget: Widget,
    /// A value of zero means the child will have it's inherent size. Any value greater than zero
    /// and the remaining space will be proportioned to each item
    flex: u8 = 1,

    pub fn init(child: Widget, flex: u8) FlexItem {
        return .{ .widget = child, .flex = flex };
    }
};

pub fn resolveConstraint(min: u16, max: u16, wants: u16) u16 {
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

pub const Point = struct {
    row: u16,
    col: u16,
};

pub const Surface = struct {
    /// Size of this surface
    size: Size,
    /// The widget this surface belongs to
    widget: Widget,

    /// Contents of this surface
    buffer: []vaxis.Cell, // len == width * height

    children: []const SubSurface,

    pub fn init(allocator: Allocator, widget: Widget, size: Size) Allocator.Error!Surface {
        const buffer = try allocator.alloc(vaxis.Cell, size.width * size.height);
        return .{
            .size = size,
            .widget = widget,
            .buffer = buffer,
            .children = &.{},
        };
    }

    pub fn writeCell(self: Surface, col: u16, row: u16, cell: vaxis.Cell) void {
        if (self.size.width <= col) return;
        if (self.size.height <= row) return;
        const i = (row * self.size.width) + col;
        assert(i < self.buffer.len);
        self.buffer[i] = cell;
    }

    /// Creates a new surface of the same width, with the buffer trimmed to a given height
    pub fn trimHeight(self: Surface, height: u16) Surface {
        assert(height <= self.size.height);
        return .{
            .size = .{ .width = self.size.width, .height = height },
            .widget = self.widget,
            .buffer = self.buffer[0 .. self.size.width * height],
            .children = self.children,
        };
    }
};

pub const SubSurface = struct {
    /// Origin relative to parent
    origin: Point,
    /// This surface
    surface: Surface,
    /// z-index relative to siblings
    z_index: u8,
};

pub const Canvas = struct {
    arena: std.mem.Allocator,
    screen: *vaxis.Screen,
    /// This slice is the size of the screen and stores the widget responsible for drawing each cell
    owners: []?Widget,

    // offset from origin of screen
    x_off: u16,
    y_off: u16,

    // constraints
    min: Size,
    max: Size,

    pub fn writeCell(self: Canvas, col: u16, row: u16, cell: vaxis.Cell) void {
        if (self.max.height == 0 or self.max.width == 0) return;
        if (self.max.height <= row or self.max.width <= col) return;
        self.screen.writeCell(col + self.x_off, row + self.y_off, cell);
    }

    pub fn stringWidth(self: Canvas, str: []const u8) usize {
        return vaxis.gwidth.gwidth(
            str,
            self.screen.width_method,
            &self.screen.unicode.width_data,
        );
    }

    /// Clears the *entire* screen
    pub fn clear(self: Canvas) void {
        @memset(self.screen.buf, .{ .default = true });
    }

    /// Creates a temporary Canvas with size max, used to layout a child widget.
    pub fn layoutCanvas(self: Canvas, min: Size, max: Size) !Canvas {
        const screen = try self.arena.create(vaxis.Screen);
        screen.* = try vaxis.Screen.init(
            self.arena,
            .{ .rows = max.height, .cols = max.width, .x_pixel = 0, .y_pixel = 0 },
            self.screen.unicode,
        );
        screen.width_method = self.screen.width_method;
        return .{
            .arena = self.arena,
            .screen = screen,
            .x_off = 0,
            .y_off = 0,
            .min = min,
            .max = max,
        };
    }

    /// Copy the contents from src to dst
    pub fn copyRegion(
        dst: Canvas,
        dst_x: u16,
        dst_y: u16,
        src: Canvas,
        region: Size,
    ) void {
        for (0..region.height) |row| {
            const src_start = row * src.screen.width;
            const src_end = src_start + region.width;
            const dst_start = dst_x + ((row + dst_y) * dst.screen.width);
            const dst_end = dst_start + region.width;
            @memcpy(dst.screen.buf[dst_start..dst_end], src.screen.buf[src_start..src_end]);
        }
    }

    pub fn fillStyle(self: Canvas, style: vaxis.Style, region: Size) void {
        for (0..region.height) |row| {
            for (0..region.width) |col| {
                var cell = self.screen.readCell(col, row) orelse continue;
                cell.style = style;
                cell.default = false;
                self.screen.writeCell(col, row, cell);
            }
        }
    }
};

/// A noop event handler for widgets which don't require any event handling
pub fn noopEventHandler(_: *anyopaque, _: Context, _: Event) anyerror!void {}
