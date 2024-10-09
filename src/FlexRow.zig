const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const FlexRow = @This();

children: []const vtk.FlexItem,

pub fn widget(self: *const FlexRow) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    const self: *const FlexRow = @ptrCast(@alignCast(ptr));
    return self.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const FlexRow = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn handleEvent(self: *const FlexRow, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    for (self.children) |child| {
        try child.widget.handleEvent(ctx, event);
    }
}

pub fn draw(self: *const FlexRow, canvas: vtk.Canvas) anyerror!vtk.Size {
    if (self.children.len == 0) return .{ .width = 0, .height = 0 };

    // Calculate initial width
    const initial_width: u16 = canvas.max.width / @as(u16, @intCast(self.children.len));

    // Make a layout canvas the same size as our canvas
    var layout_canvas = try canvas.layoutCanvas(
        .{ .width = 0, .height = 0 },
        canvas.max,
    );

    // Set the max width for layout to our initial width
    layout_canvas.max = .{ .width = initial_width, .height = canvas.max.height };

    // Store the inherent size of each widget
    var size_list = std.ArrayList(u16).init(canvas.arena);
    var first_pass_width: u16 = 0;
    var total_flex: u16 = 0;
    for (self.children) |child| {
        const size = try child.widget.drawFn(child.widget.userdata, layout_canvas);
        first_pass_width += size.width;
        total_flex += child.flex;
        try size_list.append(size.width);
    }

    // Draw again, but with distributed widths
    var second_pass_width: u16 = 0;
    var max_height: u16 = 0;
    const remaining_space = canvas.max.width - first_pass_width;
    for (self.children, 1..) |child, i| {
        layout_canvas.clear();
        const inherent_width = size_list.items[i - 1];
        const child_width = if (child.flex == 0)
            inherent_width
        else if (i == self.children.len)
            // If we are the last one, we just get the remainder
            canvas.max.width - second_pass_width
        else
            inherent_width + (remaining_space * child.flex) / total_flex;

        // Enforce the size
        layout_canvas.max.width = child_width;
        layout_canvas.min.width = child_width;
        const size = try child.widget.drawFn(child.widget.userdata, layout_canvas);
        canvas.copyRegion(second_pass_width, 0, layout_canvas, size);
        max_height = @max(max_height, size.height);
        second_pass_width += size.width;
    }
    return .{ .width = second_pass_width, .height = max_height };
}
