const std = @import("std");
const vtk = @import("vtk");

const Model = struct {
    button: vtk.Button,
    text_field: vtk.TextField,
    count: usize,

    pub fn widget(self: *Model) vtk.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(_: *anyopaque, event: vtk.Event) ?vtk.Command {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) return .quit;
                return null;
            },
            .mouse => return null,
            .focus_in => return null,
            else => return null,
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) std.mem.Allocator.Error!vtk.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.button.label = try std.fmt.allocPrint(
            ctx.arena,
            "Hi, I'm a button.\nI've been clicked {d} times",
            .{self.count},
        );

        const flex: vtk.FlexRow = .{ .children = &.{ .{
            .widget = self.button.widget(),
        }, .{
            .widget = self.text_field.widget(),
        } } };

        // const center: vtk.Center = .{ .child = self.button.widget() };
        // var surface = try center.draw(ctx.withContstraints(ctx.min, .{ .width = 30, .height = 4 }));
        // surface.widget = self.widget();
        var surface = try flex.draw(ctx);
        surface.widget = self.widget();

        return surface;
    }

    fn onClick(maybe_ptr: ?*anyopaque) ?vtk.Command {
        const ptr = maybe_ptr orelse return null;
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.count +|= 1;
        return .redraw;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = try vtk.App.init(allocator);
    defer app.deinit();

    const model = try allocator.create(Model);
    defer allocator.destroy(model);
    model.* = .{
        .count = 0,
        .button = .{
            .label = "",
            .onClick = Model.onClick,
            .userdata = model,
        },
        .text_field = vtk.TextField.init(allocator, &app.vx.unicode),
    };
    defer model.text_field.deinit();

    try app.run(model.widget(), .{});
}
