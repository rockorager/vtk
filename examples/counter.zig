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

    pub fn update(ptr: *anyopaque, ctx: *vtk.Context, event: vtk.Event) anyerror!void {
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

    pub fn draw(ptr: *anyopaque, arena: std.mem.Allocator, win: vaxis.Window) anyerror!void {
        const self: *Counter = @ptrCast(@alignCast(ptr));
        const msg = try std.fmt.allocPrint(arena, "{d}", .{self.count});
        _ = try win.printSegment(.{ .text = msg }, .{});
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
