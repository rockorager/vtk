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

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vtk.EventContext, event: vtk.Event) anyerror!void {
    const self: *const SizedBox = @ptrCast(@alignCast(ptr));
    return self.child.handleEvent(ctx, event);
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const SizedBox = @ptrCast(@alignCast(ptr));
    const max: vtk.MaxSize = .{
        .width = if (ctx.max.width) |max_w| @min(max_w, self.size.width) else self.size.width,
        .height = if (ctx.max.height) |max_h| @min(max_h, self.size.height) else self.size.height,
    };
    const min: vtk.Size = .{
        .width = @max(ctx.min.width, max.width.?),
        .height = @max(ctx.min.height, max.height.?),
    };
    return self.child.draw(ctx.withConstraints(min, max));
}

test SizedBox {
    // Create a test widget that saves the constraints it was given
    const TestWidget = struct {
        min: vtk.Size,
        max: vtk.MaxSize,

        pub fn widget(self: *@This()) vtk.Widget {
            return .{
                .userdata = self,
                .eventHandler = vtk.noopEventHandler,
                .drawFn = @This().typeErasedDrawFn,
            };
        }

        fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) std.mem.Allocator.Error!vtk.Surface {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.min = ctx.min;
            self.max = ctx.max;
            return .{
                .size = ctx.min,
                .widget = self.widget(),
                .buffer = &.{},
                .children = &.{},
            };
        }
    };

    // Boiler plate draw context
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ucd = try vaxis.Unicode.init(arena.allocator());
    vtk.DrawContext.init(&ucd, .unicode);

    var draw_ctx: vtk.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 16, .height = 16 },
    };

    var test_widget: TestWidget = .{ .min = .{}, .max = .{} };

    // SizedBox tries to draw the child widget at the specified size. It will shrink to fit within
    // constraints
    const sized_box: SizedBox = .{
        .child = test_widget.widget(),
        .size = .{ .width = 10, .height = 10 },
    };

    const box_widget = sized_box.widget();
    _ = try box_widget.draw(draw_ctx);

    // The sized box is smaller than the constraints, so we should be the desired size
    try std.testing.expectEqual(sized_box.size, test_widget.min);
    try std.testing.expectEqual(sized_box.size, test_widget.max.size());

    draw_ctx.max.height = 8;
    _ = try box_widget.draw(draw_ctx);
    // The sized box is smaller than the constraints, so we should be that size
    try std.testing.expectEqual(@as(vtk.Size, .{ .width = 10, .height = 8 }), test_widget.min);
    try std.testing.expectEqual(@as(vtk.Size, .{ .width = 10, .height = 8 }), test_widget.max.size());

    draw_ctx.max.width = 8;
    _ = try box_widget.draw(draw_ctx);
    // The sized box is smaller than the constraints, so we should be that size
    try std.testing.expectEqual(@as(vtk.Size, .{ .width = 8, .height = 8 }), test_widget.min);
    try std.testing.expectEqual(@as(vtk.Size, .{ .width = 8, .height = 8 }), test_widget.max.size());
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
