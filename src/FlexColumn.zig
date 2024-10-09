const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const FlexColumn = @This();

children: []const vtk.FlexItem,

pub fn widget(self: *const FlexColumn) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const FlexColumn = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn handleEvent(self: *const FlexColumn, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    for (self.children) |child| {
        try child.widget.handleEvent(ctx, event);
    }
}

pub fn draw(self: *const FlexColumn, canvas: vtk.Canvas) anyerror!vtk.Size {
    if (self.children.len == 0) return .{ .width = 0, .height = 0 };

    // Calculate initial height
    const initial_height: u16 = canvas.max.height / @as(u16, @intCast(self.children.len));

    // Make a layout canvas the same size as our canvas
    var layout_canvas = try canvas.layoutCanvas(
        .{ .width = 0, .height = 0 },
        canvas.max,
    );

    // Set the max height for layout to our initial height
    layout_canvas.max = .{ .width = canvas.max.width, .height = initial_height };

    // Store the inherent size of each widget
    var size_list = std.ArrayList(u16).init(canvas.arena);
    var first_pass_height: u16 = 0;
    var total_flex: u16 = 0;
    for (self.children) |child| {
        const size = try child.widget.draw(layout_canvas);
        first_pass_height += size.height;
        total_flex += child.flex;
        try size_list.append(size.height);
    }

    // Draw again, but with distributed heights
    var second_pass_height: u16 = 0;
    var max_width: u16 = 0;
    const remaining_space = canvas.max.height - first_pass_height;
    for (self.children, 1..) |child, i| {
        layout_canvas.clear();
        const inherent_height = size_list.items[i - 1];
        const child_height = if (child.flex == 0)
            inherent_height
        else if (i == self.children.len)
            // If we are the last one, we just get the remainder
            canvas.max.height - second_pass_height
        else
            inherent_height + (remaining_space * child.flex) / total_flex;

        // Enforce the size
        layout_canvas.max.height = child_height;
        layout_canvas.min.height = child_height;
        const size = try child.widget.draw(layout_canvas);
        canvas.copyRegion(0, second_pass_height, layout_canvas, size);
        max_width = @max(max_width, size.width);
        second_pass_height += size.height;
    }
    return .{ .width = max_width, .height = second_pass_height };
}
