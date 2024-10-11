const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Allocator = std.mem.Allocator;

const Center = @import("Center.zig");
const Text = @import("Text.zig");

const Button = @This();

label: []const u8,
on_click: *const fn (?*anyopaque) ?vtk.Command,
userdata: ?*anyopaque = null,
style: vaxis.Style = .{ .reverse = true },
hover_style: vaxis.Style = .{ .fg = .{ .index = 3 }, .reverse = true },
mouse_down_style: vaxis.Style = .{ .fg = .{ .index = 4 }, .reverse = true },
mouse_down: bool = false,
has_mouse: bool = false,

cmds: [2]vtk.Command = [_]vtk.Command{ .consume_event, .consume_event },

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

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) ?vtk.Command {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

pub fn handleEvent(self: *Button, event: vtk.Event) ?vtk.Command {
    switch (event) {
        .mouse => |mouse| {
            if (self.mouse_down and mouse.type == .release) {
                self.mouse_down = false;
                if (self.on_click(self.userdata)) |cmd| {
                    self.cmds[0] = cmd;
                    return .{ .batch = &self.cmds };
                }
            }
            if (mouse.type == .press and mouse.button == .left) {
                self.mouse_down = true;
                self.cmds[0] = .redraw;
                return .{ .batch = &self.cmds };
            }
            if (!self.has_mouse) {
                self.has_mouse = true;

                self.cmds[0] = .{ .set_mouse_shape = .pointer };
                return .{ .batch = &self.cmds };
            }
            return .consume_event;
        },
        .mouse_leave => {
            self.has_mouse = false;
            return .{ .set_mouse_shape = .default };
        },
        else => {},
    }
    return null;
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *Button, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const style: vaxis.Style = if (self.mouse_down)
        self.mouse_down_style
    else if (self.has_mouse)
        self.hover_style
    else
        self.style;

    const text: Text = .{
        .style = style,
        .text = self.label,
        .text_align = .center,
    };

    const center: Center = .{ .child = text.widget() };
    const surf = try center.draw(ctx);
    for (0..surf.buffer.len) |i| {
        var cell = surf.buffer[i];
        cell.style = style;
        cell.default = false;
        surf.buffer[i] = cell;
    }

    // Masquerade as Center
    return .{
        .size = surf.size,
        .widget = self.widget(),
        .buffer = surf.buffer,
        .children = surf.children,
    };
}

test Button {
    const Foo = struct {
        count: u8,

        fn onClick(ptr: ?*anyopaque) void {
            const foo: *@This() = @ptrCast(@alignCast(ptr));
            foo.count +|= 1;
        }
    };

    var foo: Foo = .{ .count = 0 };

    var button: Button = .{
        .label = "Test Button",
        .on_click = Foo.onClick,
        .userdata = &foo,
    };

    _ = button.widget();
}
