const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");
const colors = @import("colors.zig");

const VxInput = vaxis.widgets.TextInput;

const TextInput = @This();

input: VxInput,
prompt: vaxis.Segment,
mouse: ?vaxis.Mouse,

pub fn init(allocator: std.mem.Allocator) TextInput {
    const input: VxInput = .{
        .buf = VxInput.Buffer.init(allocator),
        .unicode = undefined,
    };
    return .{
        .input = input,
        .prompt = .{
            .text = " ",
            .style = .{ .fg = colors.blue },
        },
        .mouse = null,
    };
}

pub fn deinit(self: *TextInput) void {
    self.input.deinit();
}

pub fn widget(self: *TextInput) vtk.Widget {
    return .{
        .userdata = self,
        .updateFn = TextInput.updateErased,
        .drawFn = TextInput.drawErased,
    };
}

pub fn updateErased(ptr: *anyopaque, ctx: *vtk.Context, event: vtk.Event) anyerror!void {
    const self: *TextInput = @ptrCast(@alignCast(ptr));
    return self.update(ctx, event);
}

pub fn update(self: *TextInput, ctx: *vtk.Context, event: vtk.Event) anyerror!void {
    // Always ensure we have unicode
    self.input.unicode = &ctx.loop.vaxis.unicode;
    switch (event) {
        .key_press => |key| {
            try self.input.update(.{ .key_press = key });
        },
        .mouse => |mouse| self.mouse = mouse,
        else => {},
    }
}

pub fn drawErased(ptr: *anyopaque, arena: std.mem.Allocator, win: vaxis.Window) anyerror!void {
    const self: *TextInput = @ptrCast(@alignCast(ptr));
    return self.draw(arena, win);
}

pub fn draw(self: *TextInput, _: std.mem.Allocator, win: vaxis.Window) anyerror!void {
    // Always ensure we have unicode
    self.input.unicode = win.screen.unicode;
    const result = try win.printSegment(self.prompt, .{});

    // Input is always 1 tall
    const input_win = win.child(.{
        .x_off = result.col,
        .height = .{ .limit = 1 },
    });
    self.input.draw(input_win);
    if (input_win.hasMouse(self.mouse)) |_| {
        self.mouse = null;
        win.screen.mouse_shape = .text;
        // TODO: Move cursor, selections, etc
    }
}
