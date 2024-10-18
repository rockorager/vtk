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
cursor: usize = 0,
/// Lines to scroll for a mouse wheel
wheel_scroll: u8 = 3,

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
                key.matches(vaxis.Key.down, .{}))
            {
                if (self.scroll.has_more) {
                    self.cursor += 1;
                    return vtk.consumeAndRedraw();
                }
                return .consume_event;
            }
            if (key.matches('k', .{}) or
                key.matches(vaxis.Key.up, .{}))
            {
                if (self.cursor == 0) {
                    return .consume_event;
                }
                self.cursor -|= 1;
                return vtk.consumeAndRedraw();
            }
        },
        else => {},
    }
    return null;
}

pub fn draw(self: *ListView, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    switch (self.children) {
        .slice => |slice| {
            const builder: SliceBuilder = .{ .slice = slice };
            return self.drawBuilder(ctx, .{ .userdata = &builder, .buildFn = SliceBuilder.build });
        },
        .builder => |b| return self.drawBuilder(ctx, b),
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

        // Set up constraints. We let the child be the entire height if it wants
        const child_ctx = ctx.withConstraints(
            .{ .width = ctx.max.width - 2, .height = 0 },
            .{ .width = ctx.max.width - 2, .height = ctx.max.height },
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
    // Set up surface
    var surface = try vtk.Surface.init(ctx.arena, self.widget(), ctx.max);

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

    while (builder.itemAtIdx(i, self.cursor)) |child| {
        // Defer the increment
        defer i += 1;

        // Set up constraints. We let the child be the entire height if it wants
        const child_ctx = ctx.withConstraints(
            .{ .width = ctx.max.width - 2, .height = 0 },
            .{ .width = ctx.max.width - 2, .height = ctx.max.height },
        );

        // Draw the child
        const surf = try child.draw(child_ctx);

        // Add the child surface to our list. It's offset from parent is the accumulated height
        try child_list.append(.{
            .origin = .{ .col = 2, .row = accumulated_height },
            .surface = surf,
            .z_index = 0,
        });

        // Accumulate the height
        accumulated_height += surf.size.height;

        // Break if we drew enough
        if (accumulated_height >= ctx.max.height) break;
    } else {
        // This branch runs if we ran out of items. Set our state accordingly
        self.scroll.has_more = false;
    }

    var total_height: usize = totalHeight(&child_list);

    // If we reached the bottom, don't have enough height to fill the screen, and have room to add
    // more, then we add more until out of items or filled the space. This can happen on a resize
    if (!self.scroll.has_more and total_height < ctx.max.height and self.scroll.top > 0) {
        try self.insertChildren(ctx, builder, &child_list, @intCast(ctx.max.height - total_height));
        // Set the new total height
        total_height = totalHeight(&child_list);
    }

    // If we reached the bottom, we need to reset origins
    if (!self.scroll.has_more and total_height < ctx.max.height) {
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
        var origin: i32 = ctx.max.height;
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
        if (child.origin.row > ctx.max.height) {
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
