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

    var app = try vtk.App.init(allocator);
    defer app.deinit();

    const root = (vtk.FlexRow{
        .children = &.{
            .{ .widget = (vtk.Text{
                .text = "abc\nsome other text",
                .text_align = .center,
                .style = .{ .reverse = true },
            }).widget(), .flex = 2 },

            .{
                .widget = (vtk.Text{
                    .text = "def\nmore text",
                    .text_align = .center,
                }).widget(),
            },

            .{ .widget = (vtk.Text{
                .text = "ghi\nHow many\nrows should we have?",
                .text_align = .center,
                .style = .{ .reverse = true },
            }).widget(), .flex = 0 },

            .{ .widget = (vtk.Text{
                .text = "jkl",
                .text_align = .center,
            }).widget() },
        },
    }).widget();

    try app.run(root, .{});
}
