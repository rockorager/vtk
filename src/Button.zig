const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Allocator = std.mem.Allocator;

const Center = @import("Center.zig");
const Text = @import("Text.zig");

const Button = @This();

// User supplied values
label: []const u8,
onClick: *const fn (?*anyopaque, ctx: *vtk.EventContext) anyerror!void,
userdata: ?*anyopaque = null,

// Styles
style: struct {
    default: vaxis.Style = .{ .reverse = true },
    mouse_down: vaxis.Style = .{ .fg = .{ .index = 4 }, .reverse = true },
    hover: vaxis.Style = .{ .fg = .{ .index = 3 }, .reverse = true },
    focus: vaxis.Style = .{ .fg = .{ .index = 5 }, .reverse = true },
} = .{},

// State
mouse_down: bool = false,
has_mouse: bool = false,
focused: bool = false,

pub fn widget(self: *Button) vtk.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vtk.EventContext, event: vtk.Event) anyerror!void {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

pub fn handleEvent(self: *Button, ctx: *vtk.EventContext, event: vtk.Event) anyerror!void {
    switch (event) {
        .key_press => |key| {
            if (key.matches(vaxis.Key.enter, .{})) {
                return self.doClick(ctx);
            }
        },
        .mouse => |mouse| {
            if (self.mouse_down and mouse.type == .release) {
                self.mouse_down = false;
                return self.doClick(ctx);
            }
            if (mouse.type == .press and mouse.button == .left) {
                self.mouse_down = true;
                return ctx.consumeAndRedraw();
            }
            if (!self.has_mouse) {
                self.has_mouse = true;

                // implicit redraw
                try ctx.setMouseShape(.pointer);
                return ctx.consumeAndRedraw();
            }
            return ctx.consumeEvent();
        },
        .mouse_leave => {
            self.has_mouse = false;
            self.mouse_down = false;
            // implicit redraw
            try ctx.setMouseShape(.default);
        },
        .focus_in => {
            self.focused = true;
            ctx.redraw = true;
        },
        .focus_out => {
            self.focused = false;
            ctx.redraw = true;
        },
        else => {},
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *Button, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const style: vaxis.Style = if (self.mouse_down)
        self.style.mouse_down
    else if (self.has_mouse)
        self.style.hover
    else if (self.focused)
        self.style.focus
    else
        self.style.default;

    const text: Text = .{
        .style = style,
        .text = self.label,
        .text_align = .center,
    };

    const center: Center = .{ .child = text.widget() };
    const surf = try center.draw(ctx);

    var button_surf = try vtk.Surface.initWithChildren(ctx.arena, self.widget(), surf.size, surf.children);
    @memset(button_surf.buffer, .{ .style = style });
    button_surf.handles_mouse = true;
    button_surf.focusable = true;
    return button_surf;
}

fn doClick(self: *Button, ctx: *vtk.EventContext) anyerror!void {
    try self.onClick(self.userdata, ctx);
    ctx.consume_event = true;
}

test Button {
    const Foo = struct {
        count: u8,

        fn onClick(ptr: ?*anyopaque, ctx: *vtk.EventContext) anyerror!void {
            const foo: *@This() = @ptrCast(@alignCast(ptr));
            foo.count +|= 1;
            ctx.consumeAndRedraw();
        }
    };

    var foo: Foo = .{ .count = 0 };

    var button: Button = .{
        .label = "Test Button",
        .onClick = Foo.onClick,
        .userdata = &foo,
    };

    _ = button.widget();
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
