const std = @import("std");
const vtk = @import("vtk");

const Model = struct {
    spinner: vtk.Spinner = .{},

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
            .init => return self.spinner.start(),
            else => return self.spinner.handleEvent(event),
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) std.mem.Allocator.Error!vtk.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        return self.spinner.draw(ctx);
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

    var app = try vtk.App.init(allocator);
    defer app.deinit();

    var model: Model = .{};

    try app.run(model.widget(), .{});
}
