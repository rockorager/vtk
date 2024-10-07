const std = @import("std");
const vtk = @import("vtk");
const vaxis = vtk.vaxis;

const App = struct {
    spinner: vtk.Spinner,

    pub fn widget(self: *App) vtk.Widget {
        return .{
            .userdata = self,
            .updateFn = App.update,
            .drawFn = App.draw,
        };
    }

    pub fn update(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ptr));
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit();
                }
            },
            else => {},
        }
        try self.spinner.update(ctx, event);
    }

    pub fn draw(ptr: *anyopaque, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
        const self: *App = @ptrCast(@alignCast(ptr));
        return self.spinner.draw(ctx, win);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    var app: App = .{ .spinner = .{} };
    app.spinner.start();

    try vtk.run(allocator, app.widget(), .{});
}
