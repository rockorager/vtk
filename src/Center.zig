const std = @import("std");
const vaxis = @import("vaxis");

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

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const Center = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn handleEvent(self: *const Center, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    return self.child.handleEvent(ctx, event);
}

pub fn draw(self: *const Center, canvas: vtk.Canvas) anyerror!vtk.Size {
    const layout_canvas = try canvas.layoutCanvas(canvas.min, canvas.max);
    const size = try self.child.drawFn(self.child.userdata, layout_canvas);

    const x = (canvas.max.width - size.width) / 2;
    const y = (canvas.max.height - size.height) / 2;
    canvas.copyRegion(x, y, layout_canvas, size);
    return canvas.max;
}
