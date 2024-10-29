const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const vtk = @import("main.zig");

const Center = @This();

child: vtk.Widget,

pub fn widget(self: *const Center) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vtk.EventContext, event: vtk.Event) anyerror!void {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.child.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

/// Cannot have unbounded constraints
pub fn draw(self: *const Center, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const child_ctx = ctx.withConstraints(.{ .width = 0, .height = 0 }, ctx.max);
    const max_size = ctx.max.size();
    const child = try self.child.draw(child_ctx);

    const x = (max_size.width - child.size.width) / 2;
    const y = (max_size.height - child.size.height) / 2;

    const children = try ctx.arena.alloc(vtk.SubSurface, 1);
    children[0] = .{
        .origin = .{ .col = x, .row = y },
        .z_index = 0,
        .surface = child,
    };

    return .{
        .size = max_size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
