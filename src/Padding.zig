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

pub fn all(padding: u16) PadValues {
    return .{
        .left = padding,
        .right = padding,
        .top = padding,
        .bottom = padding,
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
        .eventHandler = handleEventErased,
        .drawFn = drawErased,
    };
}

pub fn handleEventErased(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

pub fn handleEvent(self: *const Padding, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    return self.child.handleEvent(ctx, event);
}

pub fn drawErased(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const Padding = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn draw(self: *const Padding, canvas: vtk.Canvas) anyerror!vtk.Size {
    const pad = self.padding;
    const child_canvas: vtk.Canvas = .{
        .screen = canvas.screen,
        .arena = canvas.arena,
        .min = .{
            .width = canvas.min.width -| (pad.right + pad.left),
            .height = canvas.min.height -| (pad.top + pad.bottom),
        },
        .max = .{
            .width = canvas.max.width -| (pad.right + pad.left),
            .height = canvas.max.height -| (pad.top + pad.bottom),
        },
        .x_off = canvas.x_off + pad.left,
        .y_off = canvas.y_off + pad.top,
    };
    const child_size = try self.child.drawFn(self.child.userdata, child_canvas);
    return .{
        .width = child_size.width + (pad.right + pad.left),
        .height = child_size.height + (pad.top + pad.bottom),
    };
}
