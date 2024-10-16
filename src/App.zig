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
pub fn init(allocator: Allocator) !App {
    return .{
        .allocator = allocator,
        .tty = try vaxis.Tty.init(),
        .vx = try vaxis.init(allocator, .{ .system_clipboard_allocator = allocator }),
        .timers = std.ArrayList(vtk.Tick).init(allocator),
    };
}

pub fn deinit(self: *App) void {
    self.timers.deinit();
    self.vx.deinit(self.allocator, self.tty.anyWriter());
    self.tty.deinit();
}

pub fn run(self: *App, widget: vtk.Widget, opts: Options) anyerror!void {
    const tty = &self.tty;
    const vx = &self.vx;

    var loop: EventLoop = .{ .tty = tty, .vaxis = vx };
    try loop.start();
    defer loop.stop();

    // Send the init event
    loop.postEvent(.init);

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    {
        // This part deserves a comment. loop.init installs a signal handler for the tty. We wait to
        // init the loop until we know if we need this handler. We don't need it if the terminal
        // supports in-band-resize
        if (!vx.state.in_band_resize) try loop.init();
    }

    // HACK: Ghostty is reporting incorrect pixel screen size
    vx.caps.sgr_pixels = false;
    try vx.setMouseMode(tty.anyWriter(), true);

    // Give DrawContext the unicode data
    vtk.DrawContext.init(&vx.unicode, vx.screen.width_method);

    const framerate: u64 = if (opts.framerate > 0) opts.framerate else 60;
    // Calculate tick rate
    const tick_ms: u64 = @divFloor(std.time.ms_per_s, framerate);

    // Set up arena and context
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    var buffered = tty.bufferedWriter();

    var mouse_handler = MouseHandler.init(widget);
    var focus_handler = FocusHandler.init(self.allocator, widget);
    focus_handler.intrusiveInit();
    defer focus_handler.deinit();

    while (true) {
        std.time.sleep(tick_ms * std.time.ns_per_ms);

        try self.checkTimers();

        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    const maybe_cmd = focus_handler.handleEvent(event);
                    if (vtk.eventConsumed(maybe_cmd)) {
                        try self.handleCommand(maybe_cmd);
                    } else {
                        if (key.matches(self.quit_key.codepoint, self.quit_key.mods)) {
                            self.quit = true;
                        }
                        if (key.matches(vaxis.Key.tab, .{})) {
                            const cmd = focus_handler.focusNext();
                            try self.handleCommand(cmd);
                        }
                        if (key.matches(vaxis.Key.tab, .{ .shift = true })) {
                            const cmd = focus_handler.focusPrev();
                            try self.handleCommand(cmd);
                        }
                    }
                },
                .focus_out => try mouse_handler.mouseExit(self),
                .mouse => |mouse| try mouse_handler.handleMouse(self, mouse),
                .winsize => |ws| {
                    try vx.resize(self.allocator, buffered.writer().any(), ws);
                    try buffered.flush();
                    self.redraw = true;
                },
                else => {
                    const maybe_cmd = widget.handleEvent(event);
                    try self.handleCommand(maybe_cmd);
                },
            }
        }

        // Check if we should quit
        if (self.quit) return;

        // Check if we need a redraw
        if (!self.redraw) continue;

        self.redraw = false;
        _ = arena.reset(.retain_capacity);

        const draw_context: vtk.DrawContext = .{
            .arena = arena.allocator(),
            .min = .{ .width = 0, .height = 0 },
            .max = .{
                .width = @intCast(vx.screen.width),
                .height = @intCast(vx.screen.height),
            },
        };
        const win = vx.window();
        win.clear();
        win.hideCursor();
        win.setCursorShape(.default);
        const surface = try widget.draw(draw_context);

        const appwin: vtk.Window = .{
            .x_off = 0,
            .y_off = 0,
            .size = .{
                .width = @intCast(win.screen.width),
                .height = @intCast(win.screen.height),
            },
            .screen = win.screen,
        };

        surface.render(appwin, focus_handler.focused.widget);
        try vx.render(buffered.writer().any());
        try buffered.flush();

        // Store the last frame
        mouse_handler.last_frame = surface;
        try focus_handler.update(surface);
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
        .quit => self.quit = true,
        .set_mouse_shape => |shape| {
            self.vx.setMouseShape(shape);
            self.redraw = true;
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

const MouseHandler = struct {
    last_frame: vtk.Surface,
    maybe_last_handler: ?vtk.Widget = null,

    fn init(root: Widget) MouseHandler {
        return .{
            .last_frame = .{
                .size = .{ .width = 0, .height = 0 },
                .widget = root,
                .buffer = &.{},
                .children = &.{},
            },
            .maybe_last_handler = null,
        };
    }

    fn handleMouse(self: *MouseHandler, app: *App, mouse: vaxis.Mouse) Allocator.Error!void {
        const last_frame = self.last_frame;

        // For mouse events we store the last frame and use that for hit testing
        var hits = std.ArrayList(vtk.HitResult).init(app.allocator);
        defer hits.deinit();
        const sub: vtk.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = last_frame,
            .z_index = 0,
        };
        const mouse_point: vtk.Point = .{
            .row = @intCast(mouse.row),
            .col = @intCast(mouse.col),
        };
        if (sub.containsPoint(mouse_point)) {
            try last_frame.hitTest(&hits, mouse_point);
        }
        while (hits.popOrNull()) |item| {
            var m_local = mouse;
            m_local.col = item.local.col;
            m_local.row = item.local.row;
            const maybe_cmd = item.widget.handleEvent(.{ .mouse = m_local });
            try app.handleCommand(maybe_cmd);

            // If the event wasn't consumed, we keep passing it on
            if (!vtk.eventConsumed(maybe_cmd)) continue;

            if (self.maybe_last_handler) |last_mouse_handler| {
                if (!last_mouse_handler.eql(item.widget)) {
                    const cmd = last_mouse_handler.handleEvent(.mouse_leave);
                    try app.handleCommand(cmd);
                }
            }
            self.maybe_last_handler = item.widget;
            return;
        }

        // If no one handled the mouse, we assume it exited
        return self.mouseExit(app);
    }

    fn mouseExit(self: *MouseHandler, app: *App) Allocator.Error!void {
        if (self.maybe_last_handler) |last_handler| {
            const cmd = last_handler.handleEvent(.mouse_leave);
            try app.handleCommand(cmd);
            self.maybe_last_handler = null;
        }
    }
};

/// Maintains a tree of focusable nodes. Delivers events to the currently focused node, walking up
/// the tree until the event is handled
const FocusHandler = struct {
    arena: std.heap.ArenaAllocator,

    root: Node,
    focused: *Node,

    cmds: [2]vtk.Command,

    const Node = struct {
        widget: Widget,
        parent: ?*Node,
        children: []*Node,

        fn nextSibling(self: Node) ?*Node {
            const parent = self.parent orelse return null;
            const idx = for (0..parent.children.len) |i| {
                const node = parent.children[i];
                if (self.widget.eql(node.widget))
                    break i;
            } else unreachable;

            // Return null if last child
            if (idx == parent.children.len - 1)
                return null
            else
                return parent.children[idx + 1];
        }

        fn prevSibling(self: Node) ?*Node {
            const parent = self.parent orelse return null;
            const idx = for (0..parent.children.len) |i| {
                const node = parent.children[i];
                if (self.widget.eql(node.widget))
                    break i;
            } else unreachable;

            // Return null if first child
            if (idx == 0)
                return null
            else
                return parent.children[idx - 1];
        }

        fn lastChild(self: Node) ?*Node {
            if (self.children.len > 0)
                return self.children[self.children.len - 1]
            else
                return null;
        }

        fn firstChild(self: Node) ?*Node {
            if (self.children.len > 0)
                return self.children[0]
            else
                return null;
        }

        /// returns the next logical node in the tree
        fn nextNode(self: *Node) *Node {
            // If we have a sibling, we return it's first descendant line
            if (self.nextSibling()) |sibling| {
                var node = sibling;
                while (node.firstChild()) |child| {
                    node = child;
                }
                return node;
            }

            // If we don't have a sibling, we return our parent
            if (self.parent) |parent| return parent;

            // If we don't have a parent, we are the root and we return or first descendant
            var node = self;
            while (node.firstChild()) |child| {
                node = child;
            }
            return node;
        }

        fn prevNode(self: *Node) *Node {
            // If we have children, we return the last child descendant
            if (self.children.len > 0) {
                var node = self;
                while (node.lastChild()) |child| {
                    node = child;
                }
                return node;
            }

            // If we have siblings, we return the last descendant line of the sibling
            if (self.prevSibling()) |sibling| {
                var node = sibling;
                while (node.lastChild()) |child| {
                    node = child;
                }
                return node;
            }

            // If we don't have a sibling, we return our parent
            if (self.parent) |parent| return parent;

            // If we don't have a parent, we are the root and we return our last descendant
            var node = self;
            while (node.lastChild()) |child| {
                node = child;
            }
            return node;
        }
    };

    fn init(allocator: Allocator, root: Widget) FocusHandler {
        const node: Node = .{
            .widget = root,
            .parent = null,
            .children = &.{},
        };
        return .{
            .root = node,
            .focused = undefined,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .cmds = [_]vtk.Command{ .redraw, .redraw },
        };
    }

    fn intrusiveInit(self: *FocusHandler) void {
        self.focused = &self.root;
    }

    fn deinit(self: *FocusHandler) void {
        self.arena.deinit();
    }

    /// Update the focus list
    fn update(self: *FocusHandler, root: vtk.Surface) Allocator.Error!void {
        _ = self.arena.reset(.retain_capacity);

        var list = std.ArrayList(*Node).init(self.arena.allocator());
        for (root.children) |child| {
            try self.findFocusableChildren(&self.root, &list, child.surface);
        }
        self.root = .{
            .widget = root.widget,
            .children = list.items,
            .parent = null,
        };
    }

    /// Walks the surface tree, adding all focusable nodes to list
    fn findFocusableChildren(
        self: *FocusHandler,
        parent: *Node,
        list: *std.ArrayList(*Node),
        surface: vtk.Surface,
    ) Allocator.Error!void {
        if (surface.focusable) {
            // We are a focusable child of parent. Create a new node, and find our own focusable
            // children
            const node = try self.arena.allocator().create(Node);
            var child_list = std.ArrayList(*Node).init(self.arena.allocator());
            for (surface.children) |child| {
                try self.findFocusableChildren(node, &child_list, child.surface);
            }
            node.* = .{
                .widget = surface.widget,
                .parent = parent,
                .children = child_list.items,
            };
            try list.append(node);
        } else {
            for (surface.children) |child| {
                try self.findFocusableChildren(parent, list, child.surface);
            }
        }
    }

    fn focusNode(self: *FocusHandler, node: *Node) ?vtk.Command {
        if (self.focused.widget.eql(node.widget)) return null;

        const last_focus = self.focused;
        self.focused = node;
        const maybe_cmd1 = last_focus.widget.handleEvent(.focus_out);
        if (maybe_cmd1) |cmd1|
            self.cmds[0] = cmd1;

        const maybe_cmd2 = self.focused.widget.handleEvent(.focus_in);
        if (maybe_cmd2) |cmd2|
            self.cmds[1] = cmd2;

        if (maybe_cmd1 != null and maybe_cmd2 != null)
            return .{ .batch = &self.cmds }
        else if (maybe_cmd1 == null and maybe_cmd2 != null)
            return maybe_cmd2.?
        else if (maybe_cmd1 != null and maybe_cmd2 == null)
            return maybe_cmd1.?
        else
            return null;
    }

    /// Focuses the next focusable widget
    fn focusNext(self: *FocusHandler) ?vtk.Command {
        return self.focusNode(self.focused.nextNode());
    }

    /// Focuses the previous focusable widget
    fn focusPrev(self: *FocusHandler) ?vtk.Command {
        return self.focusNode(self.focused.prevNode());
    }

    fn handleEvent(self: *FocusHandler, event: vtk.Event) ?vtk.Command {
        var maybe_node: ?*Node = self.focused;
        while (maybe_node) |node| {
            const cmd = node.widget.handleEvent(event);
            if (vtk.eventConsumed(cmd)) return cmd;
            maybe_node = node.parent;
        }
        return null;
    }
};
