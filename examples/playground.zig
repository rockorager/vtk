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

    fn typeErasedEventHandler(_: *anyopaque, ctx: *vtk.EventContext, event: vtk.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) std.mem.Allocator.Error!vtk.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.button.label = try std.fmt.allocPrint(
            ctx.arena,
            "Hi, I'm a button.\nI've been clicked {d} times",
            .{self.count},
        );

        const flex: vtk.FlexRow = .{
            .children = &.{
                .{
                    .widget = (vtk.SizedBox{
                        .child = self.button.widget(),
                        .size = .{ .width = 24, .height = 4 },
                    }).widget(),
                },
                .{
                    .widget = (vtk.SizedBox{
                        .child = self.text_field.widget(),
                        .size = .{ .width = 24, .height = 4 },
                    }).widget(),
                },
            },
        };

        var surface = try flex.draw(ctx);
        surface.widget = self.widget();

        return surface;
    }

    fn onClick(maybe_ptr: ?*anyopaque, ctx: *vtk.EventContext) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.count +|= 1;
        return ctx.consumeAndRedraw();
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
