const std = @import("std");
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

    const app = try vtk.App.create(allocator);
    defer app.destroy();

    var spinner: vtk.Spinner = .{};
    spinner.start(app.context());

    const root = spinner.widget();

    try app.run(root, .{});
}
