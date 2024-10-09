const std = @import("std");
const vaxis = @import("vaxis");

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

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn handleEvent(self: *const Padding, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    return self.child.handleEvent(ctx, event);
}

pub fn draw(self: *const Padding, canvas: vtk.Canvas) anyerror!vtk.Size {
    const pad = self.padding;
    const inner_min: vtk.Size = .{
        .width = canvas.min.width -| (pad.right + pad.left),
        .height = canvas.min.height -| (pad.top + pad.bottom),
    };
    const inner_max: vtk.Size = .{
        .width = canvas.max.width -| (pad.right + pad.left),
        .height = canvas.max.height -| (pad.top + pad.bottom),
    };
    const layout_canvas = try canvas.layoutCanvas(inner_min, inner_max);
    const child_size = try self.child.draw(layout_canvas);

    canvas.copyRegion(pad.left, pad.top, layout_canvas, child_size);
    return .{
        .width = @min(child_size.width + (pad.right + pad.left), canvas.max.width),
        .height = @min(child_size.height + (pad.top + pad.bottom), canvas.max.height),
    };
}
