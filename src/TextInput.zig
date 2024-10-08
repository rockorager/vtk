// const std = @import("std");
// const vaxis = @import("vaxis");
//
// const vtk = @import("main.zig");
// const colors = @import("colors.zig");
//
// const assert = std.debug.assert;
//
// const VxInput = vaxis.widgets.TextInput;
//
// const TextInput = @This();
//
// input: VxInput,
// mouse: ?vaxis.Mouse,
// style: vaxis.Style = .{},
// width: ?usize = null,
// hint: ?[]const u8 = "",
// mask_char: ?[]const u8 = null,
//
// pub fn init(allocator: std.mem.Allocator) TextInput {
//     const input: VxInput = .{
//         .buf = VxInput.Buffer.init(allocator),
//         .unicode = undefined,
//     };
//     return .{
//         .input = input,
//         .mouse = null,
//         .style = .{},
//     };
// }
//
// pub fn deinit(self: *TextInput) void {
//     self.input.deinit();
// }
//
// pub fn widget(self: *TextInput) vtk.Widget {
//     return .{
//         .userdata = self,
//         .updateFn = TextInput.updateErased,
//         .drawFn = TextInput.drawErased,
//     };
// }
//
// pub fn updateErased(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
//     const self: *TextInput = @ptrCast(@alignCast(ptr));
//     return self.update(ctx, event);
// }
//
// pub fn update(self: *TextInput, ctx: vtk.Context, event: vtk.Event) anyerror!void {
//     // Always ensure we have unicode
//     self.input.unicode = &ctx.loop.vaxis.unicode;
//     switch (event) {
//         .key_press => |key| {
//             try self.input.update(.{ .key_press = key });
//         },
//         .mouse => |mouse| self.mouse = mouse,
//         else => {},
//     }
// }
//
// pub fn drawErased(ptr: *anyopaque, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
//     const self: *TextInput = @ptrCast(@alignCast(ptr));
//     return self.draw(ctx, win);
// }
//
// pub fn draw(self: *TextInput, ctx: vtk.DrawContext, win: vaxis.Window) anyerror!vtk.Size {
//     // Always ensure we have unicode
//     self.input.unicode = win.screen.unicode;
//
//     const width = vtk.resolveConstraint(ctx.min.width, win.width, self.width orelse win.width);
//     const height = vtk.Size.preferOdd(ctx.min.height, win.height, 1);
//
//     const widget_win = win.child(.{
//         .width = .{ .limit = width },
//         .height = .{ .limit = height },
//     });
//     widget_win.fill(.{ .char = .{ .grapheme = " ", .width = 1 }, .style = self.style });
//
//     const input_win = widget_win.child(.{
//         .y_off = widget_win.height / 2,
//         .height = .{ .limit = 1 },
//     });
//
//     self.input.drawWithStyle(input_win, self.style);
//     if (input_win.hasMouse(self.mouse)) |_| {
//         self.mouse = null;
//         win.screen.mouse_shape = .text;
//         // TODO: Move cursor, selections, etc
//     }
//
//     if (self.input.buf.realLength() == 0 and self.hint != null) {
//         var dim_style = self.style;
//         dim_style.dim = true;
//         _ = try input_win.printSegment(.{ .text = self.hint.?, .style = dim_style }, .{});
//     }
//
//     return .{ .width = widget_win.width, .height = widget_win.height };
// }
//
// test "TextInput.zig: draw sizing" {
//     const t = @import("test.zig");
//     const window = try t.createWindow(std.testing.allocator, 10, 10);
//     defer t.destroyWindow(std.testing.allocator, window);
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();
//
//     var input = init(std.testing.allocator);
//     const ctx: vtk.DrawContext = .{ .arena = arena.allocator(), .min = .{} };
//     {
//         // min size = 0
//         const size = try input.draw(ctx, window);
//         try std.testing.expectEqual(10, size.width);
//         try std.testing.expectEqual(1, size.height);
//     }
//     {
//         // min size = 3 (odd number)
//         const size = try input.draw(ctx.withMinSize(.{ .height = 3 }), window);
//         try std.testing.expectEqual(10, size.width);
//         try std.testing.expectEqual(3, size.height);
//     }
//     {
//         // min size = 4 (odd number, can increase)
//         const size = try input.draw(ctx.withMinSize(.{ .height = 4 }), window);
//         try std.testing.expectEqual(10, size.width);
//         try std.testing.expectEqual(5, size.height);
//     }
//     {
//         // min size = max size
//         const size = try input.draw(ctx.withMinSize(.{ .height = 10 }), window);
//         try std.testing.expectEqual(10, size.width);
//         try std.testing.expectEqual(10, size.height);
//     }
//     {
//         // limit width
//         input.width = 4;
//         const size = try input.draw(ctx.withMinSize(.{ .height = 1 }), window);
//         try std.testing.expectEqual(4, size.width);
//         try std.testing.expectEqual(1, size.height);
//     }
//     {
//         // ignore min width if no width set
//         input.width = null;
//         const size = try input.draw(ctx.withMinSize(.{ .width = 4 }), window);
//         try std.testing.expectEqual(10, size.width);
//         try std.testing.expectEqual(1, size.height);
//     }
//     {
//         // respect min_width
//         input.width = 2;
//         const size = try input.draw(ctx.withMinSize(.{ .width = 4 }), window);
//         try std.testing.expectEqual(4, size.width);
//         try std.testing.expectEqual(1, size.height);
//     }
// }
