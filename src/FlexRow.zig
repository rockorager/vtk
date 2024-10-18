const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Allocator = std.mem.Allocator;

const FlexRow = @This();

children: []const vtk.FlexItem,

pub fn widget(self: *const FlexRow) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = vtk.noopEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const FlexRow = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *const FlexRow, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    std.debug.assert(ctx.max.height != null);
    std.debug.assert(ctx.max.width != null);
    if (self.children.len == 0) return vtk.Surface.init(ctx.arena, self.widget(), ctx.min);

    // Store the inherent size of each widget
    const size_list = try ctx.arena.alloc(u16, self.children.len);

    var layout_arena = std.heap.ArenaAllocator.init(ctx.arena);

    const layout_ctx: vtk.DrawContext = .{
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = null, .height = ctx.max.height },
        .arena = layout_arena.allocator(),
    };

    var first_pass_width: u16 = 0;
    var total_flex: u16 = 0;
    for (self.children, 0..) |child, i| {
        const surf = try child.widget.draw(layout_ctx);
        first_pass_width += surf.size.width;
        total_flex += child.flex;
        size_list[i] = surf.size.width;
    }

    // We are done with the layout arena
    layout_arena.deinit();

    // make our children list
    var children = std.ArrayList(vtk.SubSurface).init(ctx.arena);

    // Draw again, but with distributed widths
    var second_pass_width: u16 = 0;
    var max_height: u16 = 0;
    const remaining_space = ctx.max.width.? - first_pass_width;
    for (self.children, 1..) |child, i| {
        const inherent_width = size_list[i - 1];
        const child_width = if (child.flex == 0)
            inherent_width
        else if (i == self.children.len)
            // If we are the last one, we just get the remainder
            ctx.max.width.? - second_pass_width
        else
            inherent_width + (remaining_space * child.flex) / total_flex;

        // Create a context for the child
        const child_ctx = ctx.withConstraints(
            .{ .width = child_width, .height = 0 },
            .{ .width = child_width, .height = ctx.max.height.? },
        );
        const surf = try child.widget.draw(child_ctx);

        try children.append(.{
            .origin = .{ .col = second_pass_width, .row = 0 },
            .surface = surf,
            .z_index = 0,
        });
        max_height = @max(max_height, surf.size.height);
        second_pass_width += surf.size.width;
    }
    const size = .{ .width = second_pass_width, .height = max_height };
    return vtk.Surface.initWithChildren(ctx.arena, self.widget(), size, children.items);
}

test "FlexRow: validate widget interface" {
    var flex: FlexRow = .{ .children = &.{} };
    _ = flex.widget();
}
