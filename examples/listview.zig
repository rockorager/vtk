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

    const rows = [_]vtk.Widget{
        (vtk.Text{ .text = "Item 1\n  ├─line 2\n  ├─line 3\n  ├─line 4\n  └─line 5" }).widget(),
        (vtk.Text{ .text = "Item 2" }).widget(),
        (vtk.Text{ .text = "Item 3" }).widget(),
        (vtk.Text{ .text = "Item 4" }).widget(),
        (vtk.Text{ .text = "Item 5" }).widget(),
        (vtk.Text{ .text = "Item 6" }).widget(),
        (vtk.Text{ .text = "Item 7" }).widget(),
        (vtk.Text{ .text = "Item 8" }).widget(),
        (vtk.Text{ .text = "Item 9" }).widget(),
        (vtk.Text{ .text = "Item 10" }).widget(),
        (vtk.Text{ .text = "Item 11" }).widget(),
        (vtk.Text{ .text = "Item 12" }).widget(),
        (vtk.Text{ .text = "Item 13" }).widget(),
        (vtk.Text{ .text = "Item 14" }).widget(),
        (vtk.Text{ .text = "Item 15\n  ├─line 2\n  ├─line 3\n  ├─line 4\n  └─line 5" }).widget(),
        (vtk.Text{ .text = "Item 16" }).widget(),
        (vtk.Text{ .text = "Item 17" }).widget(),
        (vtk.Text{ .text = "Item 18" }).widget(),
        (vtk.Text{ .text = "Item 19" }).widget(),
        (vtk.Text{ .text = "Item 20" }).widget(),
        (vtk.Text{ .text = "Item 21" }).widget(),
        (vtk.Text{ .text = "Item 22" }).widget(),
        (vtk.Text{ .text = "Item 23" }).widget(),
        (vtk.Text{ .text = "Item 24" }).widget(),
        (vtk.Text{ .text = "Item 25" }).widget(),
        (vtk.Text{ .text = "Item 26" }).widget(),
        (vtk.Text{ .text = "Item 27" }).widget(),
        (vtk.Text{ .text = "Item 28" }).widget(),
        (vtk.Text{ .text = "Item 29\n  ├─line 2\n  ├─line 3\n  ├─line 4\n  └─line 5" }).widget(),
    };

    var app = try vtk.App.init(allocator);
    defer app.deinit();

    const root = (vtk.ListView{
        .children = .{ .slice = &rows },
    }).widget();

    try app.run(root, .{});
}
