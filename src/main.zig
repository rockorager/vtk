const std = @import("std");
pub const vaxis = @import("vaxis");

const grapheme = vaxis.grapheme;

const assert = std.debug.assert;
const testing = std.testing;

const Allocator = std.mem.Allocator;

pub const App = @import("App.zig");

// Layout widgets
pub const Center = @import("Center.zig");
pub const FlexColumn = @import("FlexColumn.zig");
pub const FlexRow = @import("FlexRow.zig");
pub const Padding = @import("Padding.zig");
pub const SizedBox = @import("SizedBox.zig");

// Interactive
pub const Button = @import("Button.zig");
pub const TextField = @import("TextField.zig");

// Animated
pub const Spinner = @import("Spinner.zig");

// Static
pub const Text = @import("Text.zig");

const log = std.log.scoped(.vtk);

const consume_and_redraw = [2]Command{ .consume_event, .redraw };

pub const AppEvent = struct {
    name: []const u8,
    data: ?*const anyopaque = null,
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
    tick, // An event from a Tick command
    init, // sent when the application starts
    mouse_leave, // The mouse has left the widget
};

pub const Tick = struct {
    deadline_ms: i64,
    widget: Widget,

    pub fn lessThan(_: void, lhs: Tick, rhs: Tick) bool {
        return lhs.deadline_ms > rhs.deadline_ms;
    }

    pub fn in(ms: u32, widget: Widget) Command {
        const now = std.time.milliTimestamp();
        return .{ .tick = .{
            .deadline_ms = now + ms,
            .widget = widget,
        } };
    }
};

pub const Command = union(enum) {
    /// Callback the event with a tick event at the specified deadlline
    tick: Tick,
    /// The event was handled, do not pass it on
    consume_event,
    /// The event produced multiple commands. The lifetime of the slice must be at least one frame
    batch: []const Command,
    /// Tells the event loop to redraw the UI
    redraw,
    /// Quit the application
    quit,
    /// Change the mouse shape. This also has an implicit redraw
    set_mouse_shape: vaxis.Mouse.Shape,
};

/// Returns true if the Command contains a .consume_event event
pub fn eventConsumed(maybe_cmd: ?Command) bool {
    const cmd = maybe_cmd orelse return false;
    switch (cmd) {
        .consume_event => return true,
        .batch => |cmds| {
            for (cmds) |c| {
                if (eventConsumed(c)) return true;
            }
            return false;
        },

        // The rest are false
        .tick,
        .redraw,
        .quit,
        .set_mouse_shape,
        => return false,
    }
}

/// Returns a batch command composed of a consume_event and a redraw command
pub fn consumeAndRedraw() Command {
    return .{ .batch = &consume_and_redraw };
}

pub const DrawContext = struct {
    // Allocator backed by an arena. Widgets do not need to free their own resources, they will be
    // freed after rendering
    arena: std.mem.Allocator,
    // Constraints
    min: Size,
    max: Size,

    // Unicode stuff
    var unicode: ?*const vaxis.Unicode = null;
    var width_method: vaxis.gwidth.Method = .unicode;

    pub fn init(ucd: *const vaxis.Unicode, method: vaxis.gwidth.Method) void {
        DrawContext.unicode = ucd;
        DrawContext.width_method = method;
    }

    pub fn stringWidth(_: DrawContext, str: []const u8) usize {
        assert(DrawContext.unicode != null); // DrawContext not initialized
        return vaxis.gwidth.gwidth(
            str,
            DrawContext.width_method,
            &DrawContext.unicode.?.width_data,
        );
    }

    pub fn graphemeIterator(_: DrawContext, str: []const u8) grapheme.Iterator {
        assert(DrawContext.unicode != null); // DrawContext not initialized
        return DrawContext.unicode.?.graphemeIterator(str);
    }

    pub fn withConstraints(self: DrawContext, min: Size, max: Size) DrawContext {
        return .{
            .arena = self.arena,
            .min = min,
            .max = max,
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
    eventHandler: *const fn (userdata: *anyopaque, event: Event) ?Command,
    drawFn: *const fn (userdata: *anyopaque, ctx: DrawContext) Allocator.Error!Surface,

    pub fn handleEvent(self: Widget, event: Event) ?Command {
        return self.eventHandler(self.userdata, event);
    }

    pub fn draw(self: Widget, ctx: DrawContext) Allocator.Error!Surface {
        return self.drawFn(self.userdata, ctx);
    }

    /// Returns true if the Widgets point to the same widget instance
    pub fn eql(self: Widget, other: Widget) bool {
        return @intFromPtr(self.userdata) == @intFromPtr(other.userdata) and
            @intFromPtr(self.eventHandler) == @intFromPtr(other.eventHandler) and
            @intFromPtr(self.drawFn) == @intFromPtr(other.drawFn);
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

/// Result of a hit test
pub const HitResult = struct {
    local: Point,
    widget: Widget,
};

pub const CursorState = struct {
    /// Local coordinates
    row: u16,
    /// Local coordinates
    col: u16,
    shape: vaxis.Cell.CursorShape = .default,
};

pub const Surface = struct {
    /// Size of this surface
    size: Size,
    /// The widget this surface belongs to
    widget: Widget,

    /// If this widget / Surface is focusable
    focusable: bool = false,
    /// If this widget can handle mouse events
    handles_mouse: bool = false,

    /// Cursor state
    cursor: ?CursorState = null,

    /// Contents of this surface. len == width * height
    buffer: []vaxis.Cell,

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
            .focusable = self.focusable,
            .handles_mouse = self.handles_mouse,
        };
    }

    /// Walks the Surface tree to produce a list of all widgets that intersect Point. Point will
    /// always be translated to local Surface coordinates. Asserts that this Surface does contain Point
    pub fn hitTest(self: Surface, list: *std.ArrayList(HitResult), point: Point) Allocator.Error!void {
        assert(point.col < self.size.width and point.row < self.size.height);
        if (self.handles_mouse)
            try list.append(.{ .local = point, .widget = self.widget });
        for (self.children) |child| {
            if (!child.containsPoint(point)) continue;
            const child_point: Point = .{
                .row = point.row - child.origin.row,
                .col = point.col - child.origin.col,
            };
            try child.surface.hitTest(list, child_point);
        }
    }

    /// Copies all cells from Surface to Window
    pub fn render(self: Surface, win: vaxis.Window, focused: Widget) void {
        // render self first
        for (0..self.size.height) |row| {
            for (0..self.size.width) |col| {
                const cell = self.readCell(col, row);
                win.writeCell(col, row, cell);
            }
        }

        if (self.cursor) |cursor| {
            if (self.widget.eql(focused)) {
                win.showCursor(cursor.col, cursor.row);
                win.setCursorShape(cursor.shape);
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
            child.surface.render(child_win, focused);
        }
    }

    /// Returns true if the surface satisfies a set of constraints
    pub fn satisfiesConstraints(self: Surface, min: Size, max: Size) bool {
        return self.size.width < min.width and
            self.size.width > max.width and
            self.size.height < min.height and
            self.size.height > max.height;
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

    /// Returns true if this SubSurface contains Point. Point must be in parent local units
    pub fn containsPoint(self: SubSurface, point: Point) bool {
        return point.col >= self.origin.col and
            point.row >= self.origin.row and
            point.col < (self.origin.col + self.surface.size.width) and
            point.row < (self.origin.row + self.surface.size.height);
    }
};

/// A noop event handler for widgets which don't require any event handling
pub fn noopEventHandler(_: *anyopaque, _: Event) ?Command {
    return null;
}

test {
    std.testing.refAllDecls(@This());
}

test "SubSurface: containsPoint" {
    const surf: SubSurface = .{
        .origin = .{ .row = 2, .col = 2 },
        .surface = .{
            .size = .{ .width = 10, .height = 10 },
            .widget = undefined,
            .children = &.{},
            .buffer = &.{},
        },
        .z_index = 0,
    };

    try testing.expect(surf.containsPoint(.{ .row = 2, .col = 2 }));
    try testing.expect(surf.containsPoint(.{ .row = 3, .col = 3 }));
    try testing.expect(surf.containsPoint(.{ .row = 11, .col = 11 }));

    try testing.expect(!surf.containsPoint(.{ .row = 1, .col = 1 }));
    try testing.expect(!surf.containsPoint(.{ .row = 12, .col = 12 }));
    try testing.expect(!surf.containsPoint(.{ .row = 2, .col = 12 }));
    try testing.expect(!surf.containsPoint(.{ .row = 12, .col = 2 }));
}
