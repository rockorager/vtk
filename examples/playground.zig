const std = @import("std");
const vtk = @import("vtk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    const app = try vtk.App.create(allocator);
    defer app.destroy();

    var button = vtk.Button.init("Hello, World!", null, onClick);

    const root = (vtk.Center{
        .child = (vtk.Padding{
            .child = button.widget(),
            .padding = vtk.Padding.all(10),
        }).widget(),
    }).widget();

    try app.run(root, .{});
}

fn onClick(_: ?*anyopaque) void {
    std.log.err("clicked", .{});
}
