const std = @import("std");
const vtk = @import("vtk");
const vaxis = vtk.vaxis;

const App = struct {
    button: vtk.Button,
    clicks: u64 = 0,

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
        try self.button.update(ctx, event);
    }

    pub fn draw(ptr: *anyopaque, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
        const self: *App = @ptrCast(@alignCast(ptr));
        const child = win.child(.{
            .x_off = 2,
            .y_off = 2,
            .width = .{ .limit = 20 },
            .height = .{ .limit = 3 },
        });
        _ = try self.button.draw(ctx, child);

        const center = win.child(.{
            .x_off = 2,
            .y_off = 8,
        });
        const msg = switch (self.clicks) {
            1 => try std.fmt.allocPrint(ctx.arena, "Button has been clicked {d} times", .{self.clicks}),
            else => try std.fmt.allocPrint(ctx.arena, "Button has been clicked {d} times", .{self.clicks}),
        };
        _ = try center.printSegment(.{ .text = msg }, .{});
        return .{};
    }

    pub fn on_click(userdata: ?*anyopaque) void {
        if (userdata) |ptr| {
            const self: *App = @ptrCast(@alignCast(ptr));
            self.clicks +|= 1;
        }
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

    var app: App = .{ .button = undefined };

    app.button = vtk.Button.init("Hello, World!", &app, App.on_click);

    try vtk.run(allocator, app.widget(), .{});
}
