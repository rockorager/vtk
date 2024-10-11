const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const vtk = @import("main.zig");

const Padding = @This();
const PadValues = struct {
    left: u16 = 0,
    right: u16 = 0,
    top: u16 = 0,
    bottom: u16 = 0,
};

child: vtk.Widget,
padding: PadValues = .{},

/// Vertical padding will be divided by 2 to approximate equal padding
pub fn all(padding: u16) PadValues {
    return .{
        .left = padding,
        .right = padding,
        .top = padding / 2,
        .bottom = padding / 2,
    };
}

pub fn horizontal(padding: u16) PadValues {
    return .{
        .left = padding,
        .right = padding,
    };
}

pub fn vertical(padding: u16) PadValues {
    return .{
        .top = padding,
        .bottom = padding,
    };
}

pub fn widget(self: *const Padding) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) ?vtk.Command {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn handleEvent(self: *const Padding, event: vtk.Event) ?vtk.Command {
    return self.child.handleEvent(event);
}

pub fn draw(self: *const Padding, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const pad = self.padding;
    const inner_min: vtk.Size = .{
        .width = ctx.min.width -| (pad.right + pad.left),
        .height = ctx.min.height -| (pad.top + pad.bottom),
    };
    const inner_max: vtk.Size = .{
        .width = ctx.max.width -| (pad.right + pad.left),
        .height = ctx.max.height -| (pad.top + pad.bottom),
    };

    const child_surface = try self.child.draw(ctx.withContstraints(inner_min, inner_max));

    const children = try ctx.arena.alloc(vtk.SubSurface, 1);
    children[0] = .{
        .surface = child_surface,
        .z_index = 0,
        .origin = .{ .row = pad.top, .col = pad.left },
    };

    const size = .{
        .width = child_surface.size.width + (pad.right + pad.left),
        .height = child_surface.size.height + (pad.top + pad.bottom),
    };

    // Create the padding surface
    return vtk.Surface.initWithChildren(ctx.arena, self.widget(), size, children);
}

test "Padding satisfies Widget interface" {
    const padding: Padding = .{ .child = undefined, .padding = .{} };
    _ = padding.widget();
}
