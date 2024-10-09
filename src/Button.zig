const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Center = @import("Center.zig");
const Text = @import("Text.zig");

const Button = @This();

label: []const u8,
on_click: *const fn (?*anyopaque) void,
userdata: ?*anyopaque = null,
style: vaxis.Style = .{ .reverse = true },
hover_style: vaxis.Style = .{ .fg = .{ .index = 3 }, .reverse = true },
mouse_down_style: vaxis.Style = .{ .fg = .{ .index = 4 }, .reverse = true },
mouse_down: bool = false,
mouse: ?vaxis.Mouse = null,

pub fn init(
    label: []const u8,
    userdata: ?*anyopaque,
    on_click: *const fn (?*anyopaque) void,
) Button {
    return .{
        .label = label,
        .userdata = userdata,
        .on_click = on_click,
    };
}

pub fn widget(self: *Button) vtk.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

pub fn handleEvent(self: *Button, _: vtk.Context, event: vtk.Event) anyerror!void {
    switch (event) {
        .mouse => |mouse| self.mouse = mouse,
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn draw(self: *Button, canvas: vtk.Canvas) anyerror!vtk.Size {
    const text: Text = .{
        .style = self.style,
        .text = self.label,
        .text_align = .center,
    };

    const center: Center = .{ .child = text.widget() };
    const size = try center.draw(canvas);

    canvas.fillStyle(self.style, size);
    return size;
}
