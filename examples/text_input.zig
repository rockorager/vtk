const std = @import("std");
const vtk = @import("vtk");
const vaxis = vtk.vaxis;

const App = struct {
    text_input: vtk.TextInput,

    pub fn widget(self: *App) vtk.Widget {
        return .{
            .userdata = self,
            .updateFn = App.update,
            .drawFn = App.draw,
        };
    }

    pub fn update(ptr: *anyopaque, ctx: *vtk.Context, event: vtk.Event) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ptr));
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit();
                    self.text_input.deinit();
                }
            },
            else => {},
        }
        try self.text_input.update(ctx, event);
    }

    pub fn draw(ptr: *anyopaque, arena: std.mem.Allocator, win: vaxis.Window) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ptr));
        return self.text_input.draw(arena, win);
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

    const input = vtk.TextInput.init(allocator);
    var app: App = .{ .text_input = input };

    try vtk.run(allocator, app.widget(), .{});
}
