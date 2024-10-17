const std = @import("std");
const vaxis = @import("vaxis");
const vtk = @import("vtk");

const lorem_ipsum =
    \\Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce finibus odio eu tellus dignissim finibus. Nullam tristique erat elit, commodo faucibus turpis consequat et. Ut vitae elit ex. Cras aliquam ante at nisi dapibus, placerat eleifend ligula interdum. Proin auctor tempus magna, sed luctus lorem scelerisque ac. Cras id diam leo. Curabitur ultrices tempus massa quis porta. Aenean in augue quis sapien mollis ullamcorper quis et dui. Vivamus ornare velit ut magna semper tincidunt. Nam id leo ipsum. Fusce non maximus lectus. Etiam tempus quam ut molestie eleifend.
    \\
    \\Suspendisse a nisi vitae nunc vulputate rutrum eu nec nulla. Morbi id sapien eros. Vivamus sit amet venenatis sem. Aliquam velit eros, finibus eget dapibus non, semper et nisl. Nulla consectetur venenatis lacinia. Pellentesque vel turpis sapien. Praesent ipsum sem, eleifend sit amet ullamcorper et, sagittis elementum sem.
    \\
    \\Cras consequat sit amet erat vel fringilla. Nullam eu elementum orci. Vestibulum ut iaculis dolor. Nulla sit amet congue augue, in laoreet libero. Nulla sodales erat eget sollicitudin ultricies. Etiam in urna quis neque imperdiet bibendum. Nulla ac tortor tristique, luctus lorem et, vehicula dolor. 
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var color: u8 = 0;
    var list = std.ArrayList(vtk.RichText.TextSpan).init(arena.allocator());
    for (lorem_ipsum) |b| {
        const char = try std.fmt.allocPrint(arena.allocator(), "{c}", .{b});
        try list.append(.{
            .text = char,
            .style = .{ .fg = .{ .index = color } },
        });
        color +%= 1;
    }

    var app = try vtk.App.init(allocator);
    defer app.deinit();

    const root = (vtk.Center{
        .child = (vtk.Padding{
            .child = (vtk.RichText{
                .text = list.items,
                .text_align = .center,
            }).widget(),
            .padding = vtk.Padding.horizontal(24),
        }).widget(),
    }).widget();

    try app.run(root, .{});
}
