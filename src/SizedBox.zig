const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const vtk = @import("main.zig");

const SizedBox = @This();

child: vtk.Widget,
size: vtk.Size,

pub fn widget(self: *const SizedBox) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) anyerror!?vtk.Command {
    const self: *const SizedBox = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const SizedBox = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn handleEvent(self: *const SizedBox, event: vtk.Event) anyerror!?vtk.Command {
    return self.child.handleEvent(event);
}

/// SizedBox does not appear in the Surface tree
pub fn draw(self: *const SizedBox, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const max: vtk.MaxSize = .{
        .width = @max(ctx.min.width, self.size.width),
        .height = @max(ctx.min.height, self.size.height),
    };
    const min: vtk.Size = .{
        .width = if (ctx.max.width) |max_w| @min(max_w, self.size.width) else self.size.width,
        .height = if (ctx.max.height) |max_h| @min(max_h, self.size.height) else self.size.height,
    };
    return self.child.draw(ctx.withConstraints(min, max));
}

test "SizedBox satisfies Widget interface" {
    const box: SizedBox = .{ .child = undefined, .size = .{ .width = 0, .height = 0 } };
    _ = box.widget();
}
