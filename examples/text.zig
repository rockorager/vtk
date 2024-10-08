const std = @import("std");
const vtk = @import("vtk");
const vaxis = vtk.vaxis;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    var app: vtk.App = .{
        .root = (vtk.Center{
            .child = (vtk.Text{
                .text = "Hello, \nworld",
            }).widget(),
        }).widget(),
    };

    try app.run(allocator);
}
