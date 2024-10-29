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

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vtk.EventContext, event: vtk.Event) anyerror!void {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.child.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *const Padding, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const pad = self.padding;
    if (pad.left > 0 or pad.right > 0)
        std.debug.assert(ctx.max.width != null);
    if (pad.top > 0 or pad.bottom > 0)
        std.debug.assert(ctx.max.height != null);
    const inner_min: vtk.Size = .{
        .width = ctx.min.width -| (pad.right + pad.left),
        .height = ctx.min.height -| (pad.top + pad.bottom),
    };

    const max_width: ?u16 = if (ctx.max.width) |max|
        max -| (pad.right + pad.left)
    else
        null;
    const max_height: ?u16 = if (ctx.max.height) |max|
        max -| (pad.top + pad.bottom)
    else
        null;

    const inner_max: vtk.MaxSize = .{
        .width = max_width,
        .height = max_height,
    };

    const child_surface = try self.child.draw(ctx.withConstraints(inner_min, inner_max));

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
    return .{
        .size = size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}

test "Padding satisfies Widget interface" {
    const padding: Padding = .{ .child = undefined, .padding = .{} };
    _ = padding.widget();
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
