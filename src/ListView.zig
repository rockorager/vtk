const std = @import("std");
const vaxis = @import("vaxis");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

const vtk = @import("main.zig");

const ListView = @This();

pub const Builder = struct {
    userdata: *const anyopaque,
    buildFn: *const fn (*const anyopaque, idx: usize, cursor: usize) ?vtk.Widget,

    inline fn itemAtIdx(self: Builder, idx: usize, cursor: usize) ?vtk.Widget {
        return self.buildFn(self.userdata, idx, cursor);
    }
};

pub const Source = union(enum) {
    slice: []const vtk.Widget,
    builder: Builder,
};

const Scroll = struct {
    /// Index of the first fully-in-view widget
    top: u32 = 0,
    /// Line offset within the top widget.
    offset: i32 = 0,
    /// Pending scroll amount
    pending_lines: i32 = 0,
    /// If there is more room to scroll down
    has_more: bool = true,
    /// The cursor must be in the viewport
    wants_cursor: bool = false,

    fn linesDown(self: *Scroll, n: u8) bool {
        if (!self.has_more) return false;
        self.pending_lines += n;
        return true;
    }

    fn linesUp(self: *Scroll, n: u8) bool {
        if (self.top == 0 and self.offset == 0) return false;
        self.pending_lines = -1 * @as(i32, @intCast(n));
        return true;
    }
};

const cursor_indicator: vaxis.Cell = .{ .char = .{ .grapheme = "▐", .width = 1 } };

children: Source,
cursor: u32 = 0,
/// When true, the widget will draw a cursor next to the widget which has the cursor
draw_cursor: bool = true,
/// Lines to scroll for a mouse wheel
wheel_scroll: u8 = 3,
/// Set this if the exact item count is known.
item_count: ?u32 = null,

/// scroll position
scroll: Scroll = .{},

pub fn widget(self: *const ListView) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) ?vtk.Command {
    const self: *ListView = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *ListView = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn handleEvent(self: *ListView, event: vtk.Event) ?vtk.Command {
    switch (event) {
        .mouse => |mouse| {
            if (mouse.button == .wheel_up) {
                if (self.scroll.linesUp(self.wheel_scroll))
                    return vtk.consumeAndRedraw();
                return null;
            }
            if (mouse.button == .wheel_down) {
                if (self.scroll.linesDown(self.wheel_scroll))
                    return vtk.consumeAndRedraw();
                return null;
            }
        },
        .key_press => |key| {
            if (key.matches('j', .{}) or
                key.matches('n', .{ .ctrl = true }) or
                key.matches(vaxis.Key.down, .{}))
            {
                return self.nextItem();
            }
            if (key.matches('k', .{}) or
                key.matches('p', .{ .ctrl = true }) or
                key.matches(vaxis.Key.up, .{}))
            {
                return self.prevItem();
            }
            if (key.matches(vaxis.Key.escape, .{})) {
                self.ensureScroll();
                return vtk.consumeAndRedraw();
            }

            // All other keypresses go to our focused child
            switch (self.children) {
                .slice => |slice| {
                    const child = slice[self.cursor];
                    return child.handleEvent(event);
                },
                .builder => |builder| {
                    if (builder.itemAtIdx(self.cursor, self.cursor)) |child| {
                        return child.handleEvent(event);
                    }
                },
            }
        },
        else => {},
    }
    return null;
}

pub fn draw(self: *ListView, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    std.debug.assert(ctx.max.width != null);
    std.debug.assert(ctx.max.height != null);
    switch (self.children) {
        .slice => |slice| {
            self.item_count = @intCast(slice.len);
            const builder: SliceBuilder = .{ .slice = slice };
            return self.drawBuilder(ctx, .{ .userdata = &builder, .buildFn = SliceBuilder.build });
        },
        .builder => |b| return self.drawBuilder(ctx, b),
    }
}

pub fn nextItem(self: *ListView) ?vtk.Command {
    // If we have a count, we can handle this directly
    if (self.item_count) |count| {
        if (self.cursor >= count - 1) {
            return .consume_event;
        }
        self.cursor += 1;
    } else {
        switch (self.children) {
            .slice => |slice| {
                self.item_count = @intCast(slice.len);
                // If we are already at the end, don't do anything
                if (self.cursor == slice.len - 1) {
                    return .consume_event;
                }
                // Advance the cursor
                self.cursor += 1;
            },
            .builder => |builder| {
                // Save our current state
                const prev = self.cursor;
                // Advance the cursor
                self.cursor += 1;
                // Check the bounds, reversing until we get the last item
                while (builder.itemAtIdx(self.cursor, self.cursor) == null) {
                    self.cursor -|= 1;
                }
                // If we didn't change state, we don't redraw
                if (self.cursor == prev) {
                    return .consume_event;
                }
            },
        }
    }
    // Reset scroll
    self.ensureScroll();
    return vtk.consumeAndRedraw();
}

pub fn prevItem(self: *ListView) ?vtk.Command {
    if (self.cursor == 0) {
        return .consume_event;
    }

    if (self.item_count) |count| {
        // If for some reason our count changed, we handle it here
        self.cursor = @min(self.cursor - 1, count - 1);
    } else {
        switch (self.children) {
            .slice => |slice| {
                self.item_count = @intCast(slice.len);
                self.cursor = @min(self.cursor - 1, slice.len - 1);
            },
            .builder => |builder| {
                // Save our current state
                const prev = self.cursor;
                // Decrement the cursor
                self.cursor -= 1;
                // Check the bounds, reversing until we get the last item
                while (builder.itemAtIdx(self.cursor, self.cursor) == null) {
                    self.cursor -|= 1;
                }
                // If we didn't change state, we don't redraw
                if (self.cursor == prev) {
                    return .consume_event;
                }
            },
        }
    }

    // Reset scroll
    self.ensureScroll();
    return vtk.consumeAndRedraw();
}

// Only call when cursor state has changed, or we want to ensure the cursored item is in view
pub fn ensureScroll(self: *ListView) void {
    if (self.cursor <= self.scroll.top) {
        self.scroll.top = @intCast(self.cursor);
        self.scroll.offset = 0;
    } else {
        self.scroll.wants_cursor = true;
    }
}

/// Inserts children until add_height is < 0
fn insertChildren(
    self: *ListView,
    ctx: vtk.DrawContext,
    builder: Builder,
    child_list: *std.ArrayList(vtk.SubSurface),
    add_height: i32,
) Allocator.Error!void {
    assert(self.scroll.top > 0);
    self.scroll.top -= 1;
    var upheight = add_height;
    while (self.scroll.top >= 0) : (self.scroll.top -= 1) {
        // Get the child
        const child = builder.itemAtIdx(self.scroll.top, self.cursor) orelse break;

        const child_offset: u16 = if (self.draw_cursor) 2 else 0;
        const max_size = ctx.max.size();

        // Set up constraints. We let the child be the entire height if it wants
        const child_ctx = ctx.withConstraints(
            .{ .width = max_size.width - child_offset, .height = 0 },
            .{ .width = max_size.width - child_offset, .height = null },
        );

        // Draw the child
        const surf = try child.draw(child_ctx);

        // Accumulate the height. Traversing backward so do this before setting origin
        upheight -= surf.size.height;

        // Insert the child to the beginning of the list
        try child_list.insert(0, .{
            .origin = .{ .col = 2, .row = upheight },
            .surface = surf,
            .z_index = 0,
        });

        // Break if we went past the top edge, or are the top item
        if (upheight < 0 or self.scroll.top == 0) break;
    }
    // Our new offset is the "upheight"
    self.scroll.offset = upheight;
}

fn totalHeight(list: *const std.ArrayList(vtk.SubSurface)) usize {
    var result: usize = 0;
    for (list.items) |child| {
        result += child.surface.size.height;
    }
    return result;
}

fn drawBuilder(self: *ListView, ctx: vtk.DrawContext, builder: Builder) Allocator.Error!vtk.Surface {
    defer self.scroll.wants_cursor = false;

    // Get the size. asserts neither constraint is null
    const max_size = ctx.max.size();
    // Set up surface.
    var surface: vtk.Surface = .{
        .size = max_size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = &.{},
    };

    // Set state
    {
        surface.focusable = true;
        surface.handles_mouse = true;
        // Assume we have more. We only know we don't after drawing
        self.scroll.has_more = true;
    }

    var child_list = std.ArrayList(vtk.SubSurface).init(ctx.arena);

    // Accumulated height tracks how much height we have drawn. It's initial state is
    // (scroll.offset + scroll.pending_lines) lines _above_ the surface top edge.
    // Example:
    // 1. Scroll up 3 lines:
    //      pending_lines = -3
    //      offset = 0
    //      accumulated_height = -(0 + -3) = 3;
    //      Our first widget is placed at row 3, we will need to fill this in after the draw
    // 2. Scroll up 3 lines, with an offset of 4
    //      pending_lines = -3
    //      offset = 4
    //      accumulated_height = -(4 + -3) = -1;
    //      Our first widget is placed at row -1
    // 3. Scroll down 3 lines:
    //      pending_lines = 3
    //      offset = 0
    //      accumulated_height = -(0 + 3) = -3;
    //      Our first widget is placed at row -3. It's possible it consumes the entire widget. We
    //      will check for this at the end and only include visible children
    var accumulated_height: i32 = -(self.scroll.offset + self.scroll.pending_lines);

    // We handled the pending scroll by assigning accumulated_height. Reset it's state
    self.scroll.pending_lines = 0;

    // Set the initial index for our downard loop. We do this here because we might modify
    // scroll.top before we traverse downward
    var i: usize = self.scroll.top;

    // If we are on the first item, and we have an upward scroll that consumed our offset, eg
    // accumulated_height > 0, we reset state here. We can't scroll up anymore so we set
    // accumulated_height to 0.
    if (accumulated_height > 0 and self.scroll.top == 0) {
        self.scroll.offset = 0;
        accumulated_height = 0;
    }

    // If we are offset downward, insert widgets to the front of the list before traversing downard
    if (accumulated_height > 0) {
        try self.insertChildren(ctx, builder, &child_list, accumulated_height);
    }

    const child_offset: u16 = if (self.draw_cursor) 2 else 0;

    while (builder.itemAtIdx(i, self.cursor)) |child| {
        // Defer the increment
        defer i += 1;

        // Set up constraints. We let the child be the entire height if it wants
        const child_ctx = ctx.withConstraints(
            .{ .width = max_size.width - child_offset, .height = 0 },
            .{ .width = max_size.width - child_offset, .height = null },
        );

        // Draw the child
        var surf = try child.draw(child_ctx);
        // We set the child to non-focusable so that we can manage where the keyevents go
        surf.focusable = false;

        // Add the child surface to our list. It's offset from parent is the accumulated height
        try child_list.append(.{
            .origin = .{ .col = child_offset, .row = accumulated_height },
            .surface = surf,
            .z_index = 0,
        });

        // Accumulate the height
        accumulated_height += surf.size.height;

        if (self.scroll.wants_cursor and i < self.cursor)
            continue // continue if we want the cursor and haven't gotten there yet
        else if (accumulated_height >= max_size.height)
            break; // Break if we drew enough
    } else {
        // This branch runs if we ran out of items. Set our state accordingly
        self.scroll.has_more = false;
    }

    var total_height: usize = totalHeight(&child_list);

    // If we reached the bottom, don't have enough height to fill the screen, and have room to add
    // more, then we add more until out of items or filled the space. This can happen on a resize
    if (!self.scroll.has_more and total_height < max_size.height and self.scroll.top > 0) {
        try self.insertChildren(ctx, builder, &child_list, @intCast(max_size.height - total_height));
        // Set the new total height
        total_height = totalHeight(&child_list);
    }

    if (self.draw_cursor and self.cursor >= self.scroll.top) blk: {
        // The index of the cursored widget in our child_list
        const cursored_idx: u32 = self.cursor - self.scroll.top;
        // Nothing to draw if our cursor is below our viewport
        if (cursored_idx >= child_list.items.len) break :blk;

        const sub = try ctx.arena.alloc(vtk.SubSurface, 1);
        const child = child_list.items[cursored_idx];
        sub[0] = .{
            .origin = .{ .col = child_offset, .row = 0 },
            .surface = child.surface,
            .z_index = 0,
        };
        const cursor_surf = try vtk.Surface.initWithChildren(
            ctx.arena,
            self.widget(),
            .{ .width = child_offset, .height = child.surface.size.height },
            sub,
        );
        for (0..cursor_surf.size.height) |row| {
            cursor_surf.writeCell(0, @intCast(row), cursor_indicator);
        }
        child_list.items[cursored_idx] = .{
            .origin = .{ .col = 0, .row = child.origin.row },
            .surface = cursor_surf,
            .z_index = 0,
        };
    }

    // If we want the cursor, we check that the cursored widget is fully in view. If it is too
    // large, we position it so that it is the top item with a 0 offset
    if (self.scroll.wants_cursor) {
        const cursored_idx: u32 = self.cursor - self.scroll.top;
        const sub = child_list.items[cursored_idx];
        // The bottom row of the cursored widget
        const bottom = sub.origin.row + sub.surface.size.height;
        if (bottom > max_size.height) {
            // Adjust the origin by the difference
            // anchor bottom
            var origin: i32 = max_size.height;
            var idx: usize = cursored_idx + 1;
            while (idx > 0) : (idx -= 1) {
                var child = child_list.items[idx - 1];
                origin -= child.surface.size.height;
                child.origin.row = origin;
                child_list.items[idx - 1] = child;
            }
        } else if (sub.surface.size.height >= max_size.height) {
            // TODO: handle when the child is larger than our height.
            // We need to change the max constraint to be optional sizes so that we can support
            // unbounded drawing in scrollable areas
            self.scroll.top = self.cursor;
            self.scroll.offset = 0;
            child_list.deinit();
            try child_list.append(.{
                .origin = .{ .col = 0, .row = 0 },
                .surface = sub.surface,
                .z_index = 0,
            });
            total_height = sub.surface.size.height;
        }
    }

    // If we reached the bottom, we need to reset origins
    if (!self.scroll.has_more and total_height < max_size.height) {
        // anchor top
        assert(self.scroll.top == 0);
        self.scroll.offset = 0;
        var origin: i32 = 0;
        for (0..child_list.items.len) |idx| {
            var child = child_list.items[idx];
            child.origin.row = origin;
            origin += child.surface.size.height;
            child_list.items[idx] = child;
        }
    } else if (!self.scroll.has_more) {
        // anchor bottom
        var origin: i32 = max_size.height;
        var idx: usize = child_list.items.len;
        while (idx > 0) : (idx -= 1) {
            var child = child_list.items[idx - 1];
            origin -= child.surface.size.height;
            child.origin.row = origin;
            child_list.items[idx - 1] = child;
        }
    }

    var start: usize = 0;
    var end: usize = child_list.items.len;

    for (child_list.items, 0..) |child, idx| {
        if (child.origin.row <= 0 and child.origin.row + child.surface.size.height > 0) {
            start = idx;
            self.scroll.offset = -child.origin.row;
            self.scroll.top += @intCast(idx);
        }
        if (child.origin.row > max_size.height) {
            end = idx;
            break;
        }
    }

    surface.children = child_list.items[start..end];
    return surface;
}

const SliceBuilder = struct {
    slice: []const vtk.Widget,

    fn build(ptr: *const anyopaque, idx: usize, _: usize) ?vtk.Widget {
        const self: *const SliceBuilder = @ptrCast(@alignCast(ptr));
        if (idx >= self.slice.len) return null;
        return self.slice[idx];
    }
};

test "ListView: validate widget interface" {
    var flex: ListView = .{ .children = .{ .slice = &.{} } };
    _ = flex.widget();
}
