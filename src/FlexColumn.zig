const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const vtk = @import("main.zig");

const FlexColumn = @This();

children: []const vtk.FlexItem,

pub fn widget(self: *const FlexColumn) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn handleEvent(self: FlexColumn, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    for (self.children) |child| {
        try child.widget.handleEvent(ctx, event);
    }
}

pub fn draw(self: FlexColumn, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    if (self.children.len == 0) return vtk.Surface.init(ctx.arena, self.widget(), ctx.min);

    // Calculate initial height
    const initial_height: u16 = ctx.max.height / @as(u16, @intCast(self.children.len));
    // Store the inherent size of each widget
    const size_list = try ctx.arena.alloc(u16, self.children.len);

    var layout_arena = std.heap.ArenaAllocator.init(ctx.arena);

    const layout_ctx = ctx.withContraintsAndAllocator(
        .{ .width = 0, .height = 0 },
        .{ .width = ctx.max.height, .height = initial_height },
        layout_arena.allocator(),
    );

    // Store the inherent size of each widget
    var first_pass_height: u16 = 0;
    var total_flex: u16 = 0;
    for (self.children, 0..) |child, i| {
        const surf = try child.widget.draw(layout_ctx);
        first_pass_height += surf.size.height;
        total_flex += child.flex;
        size_list[i] = surf.size.height;
    }

    // We are done with the layout arena
    layout_arena.deinit();

    // make our children list
    var children = std.ArrayList(vtk.SubSurface).init(ctx.arena);

    // Draw again, but with distributed heights
    var second_pass_height: u16 = 0;
    var max_width: u16 = 0;
    const remaining_space = ctx.max.height - first_pass_height;
    for (self.children, 1..) |child, i| {
        const inherent_height = size_list[i - 1];
        const child_height = if (child.flex == 0)
            inherent_height
        else if (i == self.children.len)
            // If we are the last one, we just get the remainder
            ctx.max.height - second_pass_height
        else
            inherent_height + (remaining_space * child.flex) / total_flex;

        // Create a context for the child
        const child_ctx = ctx.withContstraints(
            .{ .width = 0, .height = child_height },
            .{ .width = ctx.max.width, .height = child_height },
        );
        const surf = try child.widget.draw(child_ctx);

        try children.append(.{
            .origin = .{ .col = 0, .row = second_pass_height },
            .surface = surf,
            .z_index = 0,
        });
        max_width = @max(max_width, surf.size.width);
        second_pass_height += surf.size.height;
    }

    const size = .{ .width = max_width, .height = second_pass_height };
    return vtk.Surface.initWithChildren(ctx.arena, self.widget(), size, children.items);
}
