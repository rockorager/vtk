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

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn handleEvent(self: Center, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    return self.child.handleEvent(ctx, event);
}

pub fn draw(self: Center, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const child = try self.child.draw(ctx);

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
