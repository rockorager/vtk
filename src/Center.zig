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

pub fn draw(self: *const Center, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const child_ctx = ctx.withConstraints(.{ .width = 0, .height = 0 }, ctx.max);
    const child = try self.child.draw(child_ctx);

    const x = (ctx.max.width - child.size.width) / 2;
    const y = (ctx.max.height - child.size.height) / 2;

    const children = try ctx.arena.alloc(vtk.SubSurface, 1);
    children[0] = .{
        .origin = .{ .col = x, .row = y },
        .z_index = 0,
        .surface = child,
    };

    return vtk.Surface.initWithChildren(ctx.arena, self.widget(), ctx.max, children);
}
