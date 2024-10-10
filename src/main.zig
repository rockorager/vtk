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
            &self.unicode.width_data,
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
};

/// The Widget interface
pub const Widget = struct {
    userdata: *anyopaque,
    eventHandler: *const fn (userdata: *anyopaque, ctx: Context, event: Event) anyerror!void,
    drawFn: *const fn (userdata: *anyopaque, ctx: DrawContext) Allocator.Error!Surface,

    pub fn handleEvent(self: Widget, ctx: Context, event: Event) anyerror!void {
        return self.eventHandler(self.userdata, ctx, event);
    }

    pub fn draw(self: Widget, ctx: DrawContext) Allocator.Error!Surface {
        return self.drawFn(self.userdata, ctx);
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

    children: []SubSurface,

    pub fn init(allocator: Allocator, widget: Widget, size: Size) Allocator.Error!Surface {
        const buffer = try allocator.alloc(vaxis.Cell, size.width * size.height);
        @memset(buffer, .{ .default = true });
        return .{
            .size = size,
            .widget = widget,
            .buffer = buffer,
            .children = &.{},
        };
    }

    pub fn initWithChildren(
        allocator: Allocator,
        widget: Widget,
        size: Size,
        children: []SubSurface,
    ) Allocator.Error!Surface {
        const buffer = try allocator.alloc(vaxis.Cell, size.width * size.height);
        @memset(buffer, .{ .default = true });
        return .{
            .size = size,
            .widget = widget,
            .buffer = buffer,
            .children = children,
        };
    }

    pub fn writeCell(self: Surface, col: u16, row: u16, cell: vaxis.Cell) void {
        if (self.size.width <= col) return;
        if (self.size.height <= row) return;
        const i = (row * self.size.width) + col;
        assert(i < self.buffer.len);
        self.buffer[i] = cell;
    }

    pub fn readCell(self: Surface, col: usize, row: usize) vaxis.Cell {
        assert(col < self.size.width and row < self.size.height);
        const i = (row * self.size.width) + col;
        assert(i < self.buffer.len);
        return self.buffer[i];
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

    pub fn render(self: Surface, win: vaxis.Window) void {
        // render self first
        for (0..self.size.height) |row| {
            for (0..self.size.width) |col| {
                const cell = self.readCell(col, row);
                win.writeCell(col, row, cell);
            }
        }

        // Sort children by z-index
        std.mem.sort(SubSurface, self.children, {}, SubSurface.lessThan);

        // for each child, we make a window and render to it
        for (self.children) |child| {
            const child_win = win.child(.{
                .x_off = child.origin.col,
                .y_off = child.origin.row,
                .width = .{ .limit = child.surface.size.width },
                .height = .{ .limit = child.surface.size.height },
            });
            child.surface.render(child_win);
        }
    }
};

pub const SubSurface = struct {
    /// Origin relative to parent
    origin: Point,
    /// This surface
    surface: Surface,
    /// z-index relative to siblings
    z_index: u8,

    pub fn lessThan(_: void, lhs: SubSurface, rhs: SubSurface) bool {
        return lhs.z_index < rhs.z_index;
    }
};

/// A noop event handler for widgets which don't require any event handling
pub fn noopEventHandler(_: *anyopaque, _: Context, _: Event) anyerror!void {}
