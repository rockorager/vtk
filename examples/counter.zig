const std = @import("std");
const vtk = @import("vtk");
const vaxis = vtk.vaxis;

const Counter = struct {
    count: u8 = 0,

    pub fn widget(self: *Counter) vtk.Widget {
        return .{
            .userdata = self,
            .updateFn = Counter.update,
            .drawFn = Counter.draw,
        };
    }

    pub fn update(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
        const self: *Counter = @ptrCast(@alignCast(ptr));
        switch (event) {
            .key_press => |key| {
                self.count +%= 1;
                if (key.matches('c', .{ .ctrl = true }))
                    ctx.quit();
            },
            else => {},
        }
    }

    pub fn draw(ptr: *anyopaque, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
        const self: *Counter = @ptrCast(@alignCast(ptr));
        const msg = try std.fmt.allocPrint(ctx.arena, "{d}", .{self.count});
        const result = try win.printSegment(.{ .text = msg }, .{});
        return .{ .width = result.col, .height = result.row };
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
    var counter: Counter = .{};

    try vtk.run(allocator, counter.widget(), .{});
}
