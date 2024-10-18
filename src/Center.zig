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

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) ?vtk.Command {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn handleEvent(self: *const Center, event: vtk.Event) ?vtk.Command {
    return self.child.handleEvent(event);
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

    return vtk.Surface.initWithChildren(ctx.arena, self.widget(), max_size, children);
}
