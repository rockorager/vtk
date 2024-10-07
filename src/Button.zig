const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");
const colors = @import("colors.zig");

const Button = @This();

label: []const u8,
on_click: *const fn (?*anyopaque) void,
userdata: ?*anyopaque = null,
style: vaxis.Style = .{ .fg = colors.blue, .reverse = true },
hover_style: vaxis.Style = .{ .fg = colors.blue, .reverse = true },
mouse_down_style: vaxis.Style = .{ .fg = colors.dark_blue, .reverse = true },
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
        .updateFn = Button.update,
        .drawFn = Button.draw,
    };
}

pub fn updateErased(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.update(ctx, event);
}

pub fn update(self: *Button, _: vtk.Context, event: vtk.Event) anyerror!void {
    switch (event) {
        .mouse => |mouse| self.mouse = mouse,
        else => {},
    }
}

pub fn drawErased(ptr: *anyopaque, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
    const self: *Button = @ptrCast(@alignCast(ptr));
    return self.draw(ctx, win);
}

pub fn draw(self: *Button, _: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
    // TODO: layout / sizing integration
    const line_count = std.mem.count(u8, self.label, "\n") + 1;
    const style = if (win.hasMouse(self.mouse)) |mouse| blk: {
        win.screen.mouse_shape = .pointer;
        switch (mouse.type) {
            .press => {
                if (mouse.button == .left)
                    self.mouse_down = true;
            },
            .release => {
                if (self.mouse_down) {
                    self.on_click(self.userdata);
                }
                self.mouse_down = false;
            },
            else => {},
        }

        if (self.mouse_down)
            break :blk self.mouse_down_style
        else
            break :blk self.hover_style;
    } else blk: {
        self.mouse_down = false;
        break :blk self.style;
    };

    win.fill(.{ .style = style });

    var row = (win.height -| line_count) / 2;
    var iter = std.mem.splitScalar(u8, self.label, '\n');
    while (iter.next()) |line| {
        const line_width = win.gwidth(line);
        const col = (win.width -| line_width) / 2;
        _ = try win.printSegment(
            .{ .text = line, .style = style },
            .{ .wrap = .none, .row_offset = row, .col_offset = col },
        );
        row += 1;
    }
    return .{};
}
