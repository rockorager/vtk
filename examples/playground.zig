const std = @import("std");
const vtk = @import("vtk");

const Model = struct {
    button: vtk.Button,
    count: usize,

    pub fn widget(self: *Model) vtk.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) ?vtk.Command {
        const self: *Model = @ptrCast(@alignCast(ptr));
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) return .quit;
                return self.button.handleEvent(event);
            },
            .mouse => return null,
            .focus_in => return null,
            else => return self.button.handleEvent(event),
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) std.mem.Allocator.Error!vtk.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.button.label = try std.fmt.allocPrint(
            ctx.arena,
            "Hi, I'm a button.\nI've been clicked {d} times",
            .{self.count},
        );

        const center: vtk.Center = .{ .child = self.button.widget() };
        var surface = try center.draw(ctx.withContstraints(ctx.min, .{ .width = 30, .height = 4 }));
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
    };

    try app.run(model.widget(), .{});
}
