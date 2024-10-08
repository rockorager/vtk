const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Text = @This();

text: []const u8,
style: vaxis.Style = .{},
text_align: enum { left, center, right } = .left,
softwrap: bool = true,
overflow: enum { ellipsis, clip } = .ellipsis,

pub fn widget(self: *const Text) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = handleEventErased,
        .drawFn = drawErased,
    };
}

pub fn handleEventErased(ptr: *anyopaque, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    _ = ptr;
    _ = ctx;
    _ = event;
}

pub fn handleEvent(self: *const Text, ctx: vtk.Context, event: vtk.Event) anyerror!void {
    _ = event; // autofix
    _ = ctx; // autofix
    _ = self; // autofix
}

pub fn drawErased(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const Text = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn draw(self: *const Text, canvas: vtk.Canvas) anyerror!vtk.Size {
    var max_width: u16 = 0;
    var line_iter: LineIterator = .{ .buf = self.text };
    var row: u16 = 0;
    while (line_iter.next()) |line| {
        const line_width = try canvas.stringWidth(line);
        const needs_wrap = line_width > canvas.max.width;
        max_width = @max(max_width, @min(line_width, canvas.max.width));
        var col: u16 = switch (self.text_align) {
            .left => 0,
            .center => if (needs_wrap) 0 else @intCast((canvas.max.width - line_width) / 2),
            .right => if (needs_wrap) 0 else @intCast(canvas.max.width - line_width),
        };
        var word_iter = std.mem.splitScalar(u8, line, ' ');
        var softwrapped: bool = false;
        defer row += 1;
        while (word_iter.next()) |word| {
            if (self.softwrap and needs_wrap) {
                const word_width = try canvas.stringWidth(word);
                if (word_width <= canvas.max.width and
                    word_width > canvas.max.width - col)
                {
                    max_width = @max(col, max_width);
                    row += 1;
                    col = 0;
                    softwrapped = true;
                }
            }
            if (col == 0 and word.len > 0) {
                // Don't write a space
            } else {
                // write a space
                canvas.writeCell(col, row, .{ .style = self.style });
                col += 1;
            }
            var char_iter = canvas.screen.unicode.graphemeIterator(word);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(word);
                const grapheme_width = try canvas.stringWidth(grapheme);
                canvas.writeCell(col, row, .{
                    .char = .{ .grapheme = grapheme, .width = grapheme_width },
                    .style = self.style,
                });
                col += @intCast(grapheme_width);
            }
        }
    }
    const region: vtk.Size = .{ .width = max_width, .height = row };
    canvas.fillStyle(self.style, region);
    return region;
}

/// Iterates a slice of bytes by linebreaks. Lines are split by '\r', '\n', or '\r\n'
pub const LineIterator = struct {
    buf: []const u8,
    index: usize = 0,
    has_break: bool = true,

    fn next(self: *LineIterator) ?[]const u8 {
        if (self.index >= self.buf.len) return null;

        const start = self.index;
        const end = std.mem.indexOfAnyPos(u8, self.buf, self.index, "\r\n") orelse {
            if (start == 0) self.has_break = false;
            self.index = self.buf.len;
            return self.buf[start..];
        };

        self.index = end;
        self.consumeCR();
        self.consumeLF();
        return self.buf[start..end];
    }

    // consumes a \n byte
    fn consumeLF(self: *LineIterator) void {
        if (self.index >= self.buf.len) return;
        if (self.buf[self.index] == '\n') self.index += 1;
    }

    // consumes a \r byte
    fn consumeCR(self: *LineIterator) void {
        if (self.index >= self.buf.len) return;
        if (self.buf[self.index] == '\r') self.index += 1;
    }
};
