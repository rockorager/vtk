const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Text = @This();

text: []const u8,
style: vaxis.Style = .{},
text_align: enum { left, center, right } = .left,
softwrap: bool = true,
overflow: enum { ellipsis, clip } = .ellipsis,
width_basis: enum { parent, longest_line } = .longest_line,

pub fn widget(self: *const Text) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = vtk.noopEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, canvas: vtk.Canvas) anyerror!vtk.Size {
    const self: *const Text = @ptrCast(@alignCast(ptr));
    return self.draw(canvas);
}

pub fn draw(self: *const Text, canvas: vtk.Canvas) anyerror!vtk.Size {
    var widest_line: u16 = switch (self.text_align) {
        .left => 0,
        .center,
        .right,
        => self.findWidestLine(canvas),
    };

    var row: u16 = 0;
    if (self.softwrap) {
        var iter = SoftwrapIterator.init(self.text, canvas);
        while (iter.next()) |line| {
            if (row >= canvas.max.height) break;
            defer row += 1;
            widest_line = @max(widest_line, line.width);
            var col: u16 = switch (self.text_align) {
                .left => 0,
                .center => (widest_line - line.width) / 2,
                .right => widest_line - line.width,
            };
            var char_iter = canvas.screen.unicode.graphemeIterator(line.bytes);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(line.bytes);
                const grapheme_width = canvas.stringWidth(grapheme);
                canvas.writeCell(col, row, .{
                    .char = .{ .grapheme = grapheme, .width = grapheme_width },
                    .style = self.style,
                });
                col += @intCast(grapheme_width);
            }
        }
    } else {
        var line_iter: LineIterator = .{ .buf = self.text };
        while (line_iter.next()) |line| {
            if (row >= canvas.max.height) break;
            const line_width = canvas.stringWidth(line);
            defer row += 1;
            const resolved_line_width = @min(canvas.max.width, line_width);
            widest_line = @max(widest_line, resolved_line_width);
            var col: u16 = switch (self.text_align) {
                .left => 0,
                .center => (canvas.max.width - resolved_line_width) / 2,
                .right => canvas.max.width - resolved_line_width,
            };
            var char_iter = canvas.screen.unicode.graphemeIterator(line);
            while (char_iter.next()) |char| {
                if (col >= canvas.max.width) break;
                const grapheme = char.bytes(line);
                const grapheme_width = canvas.stringWidth(grapheme);

                if (col + grapheme_width >= canvas.max.width and
                    line_width > canvas.max.width and
                    self.overflow == .ellipsis)
                {
                    canvas.writeCell(col, row, .{
                        .char = .{ .grapheme = "…", .width = 1 },
                        .style = self.style,
                    });
                    col = canvas.max.width;
                } else {
                    canvas.writeCell(col, row, .{
                        .char = .{ .grapheme = grapheme, .width = grapheme_width },
                        .style = self.style,
                    });
                    col += @intCast(grapheme_width);
                }
            }
        }
    }
    if (self.width_basis == .parent) widest_line = canvas.max.width;
    const region: vtk.Size = .{
        .width = @max(widest_line, canvas.min.width),
        .height = @max(row, canvas.min.height),
    };
    canvas.fillStyle(self.style, region);
    return region;
}

fn findWidestLine(self: *const Text, canvas: vtk.Canvas) u16 {
    if (self.width_basis == .parent) return canvas.max.width;
    var row: u16 = 0;
    var max_width: u16 = 0;
    if (self.softwrap) {
        var iter = SoftwrapIterator.init(self.text, canvas);
        while (iter.next()) |line| {
            if (row >= canvas.max.height) break;
            defer row += 1;
            max_width = @max(max_width, line.width);
        }
    } else {
        var line_iter: LineIterator = .{ .buf = self.text };
        while (line_iter.next()) |line| {
            if (row >= canvas.max.height) break;
            const line_width = canvas.stringWidth(line);
            defer row += 1;
            const resolved_line_width = @min(canvas.max.width, line_width);
            max_width = @max(max_width, resolved_line_width);
        }
    }
    return max_width;
}

/// Iterates a slice of bytes by linebreaks. Lines are split by '\r', '\n', or '\r\n'
pub const LineIterator = struct {
    buf: []const u8,
    index: usize = 0,

    fn next(self: *LineIterator) ?[]const u8 {
        if (self.index >= self.buf.len) return null;

        const start = self.index;
        const end = std.mem.indexOfAnyPos(u8, self.buf, self.index, "\r\n") orelse {
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

pub const SoftwrapIterator = struct {
    canvas: vtk.Canvas,
    line: []const u8 = "",
    index: usize = 0,
    hard_iter: LineIterator,

    pub const Line = struct {
        width: u16,
        bytes: []const u8,
    };

    const soft_breaks = " \t";

    fn init(buf: []const u8, canvas: vtk.Canvas) SoftwrapIterator {
        return .{
            .canvas = canvas,
            .hard_iter = .{ .buf = buf },
        };
    }

    fn next(self: *SoftwrapIterator) ?Line {
        // Advance the hard iterator
        if (self.index == self.line.len) {
            self.line = self.hard_iter.next() orelse return null;
            self.line = std.mem.trimRight(u8, self.line, " \t");
            self.index = 0;
        }

        const start = self.index;
        var cur_width: u16 = 0;
        while (self.index < self.line.len) {
            const idx = self.nextWrap();
            const word = self.line[self.index..idx];
            const next_width = self.canvas.stringWidth(word);

            if (cur_width + next_width > self.canvas.max.width) {
                // Trim the word to see if it can fit on a line by itself
                const trimmed = std.mem.trimLeft(u8, word, " \t");
                const trimmed_bytes = word.len - trimmed.len;
                // The number of bytes we trimmed is equal to the reduction in length
                const trimmed_width = next_width - trimmed_bytes;
                if (trimmed_width > self.canvas.max.width) {
                    self.index += trimmed_bytes;
                    // Won't fit on line by itself, so fit as much on this line as we can
                    var iter = self.canvas.screen.unicode.graphemeIterator(trimmed);
                    while (iter.next()) |item| {
                        const grapheme = item.bytes(trimmed);
                        const w = self.canvas.stringWidth(grapheme);
                        if (cur_width + w > self.canvas.max.width) {
                            const end = self.index;
                            self.index = std.mem.indexOfNonePos(u8, self.line, self.index, soft_breaks) orelse self.line.len;
                            return .{ .width = cur_width, .bytes = self.line[start..end] };
                        }
                        cur_width += @intCast(w);
                        self.index += grapheme.len;
                    }
                }
                // We are softwrapping, advance index to the start of the next word
                const end = self.index;
                self.index = std.mem.indexOfNonePos(u8, self.line, self.index, soft_breaks) orelse self.line.len;
                return .{ .width = cur_width, .bytes = self.line[start..end] };
            }

            self.index = idx;
            cur_width += @intCast(next_width);
        }
        return .{ .width = cur_width, .bytes = self.line[start..] };
    }

    /// Determines the index of the end of the next word
    fn nextWrap(self: *SoftwrapIterator) usize {
        // Find the first linear whitespace char
        const start_pos = std.mem.indexOfNonePos(u8, self.line, self.index, soft_breaks) orelse
            return self.line.len;
        if (std.mem.indexOfAnyPos(u8, self.line, start_pos, soft_breaks)) |idx| {
            return idx;
        }
        return self.line.len;
    }

    // consumes a \n byte
    fn consumeLF(self: *SoftwrapIterator) void {
        if (self.index >= self.buf.len) return;
        if (self.buf[self.index] == '\n') self.index += 1;
    }

    // consumes a \r byte
    fn consumeCR(self: *SoftwrapIterator) void {
        if (self.index >= self.buf.len) return;
        if (self.buf[self.index] == '\r') self.index += 1;
    }
};

test "SoftwrapIterator: LF breaks" {
    const t = @import("test.zig");
    const canvas = try t.createCanvas(std.testing.allocator, 20, 10);
    defer t.destroyCanvas(std.testing.allocator, canvas);
    var iter = SoftwrapIterator.init("Hello, \n world", canvas);
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello,", first.?.bytes);
    try std.testing.expectEqual(6, first.?.width);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings(" world", second.?.bytes);
    try std.testing.expectEqual(6, second.?.width);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "SoftwrapIterator: soft breaks that fit" {
    const t = @import("test.zig");
    const canvas = try t.createCanvas(std.testing.allocator, 6, 10);
    defer t.destroyCanvas(std.testing.allocator, canvas);
    var iter = SoftwrapIterator.init("Hello, \nworld", canvas);
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello,", first.?.bytes);
    try std.testing.expectEqual(6, first.?.width);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings("world", second.?.bytes);
    try std.testing.expectEqual(5, second.?.width);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "SoftwrapIterator: soft breaks that are longer than width" {
    const t = @import("test.zig");
    const canvas = try t.createCanvas(std.testing.allocator, 6, 10);
    defer t.destroyCanvas(std.testing.allocator, canvas);
    var iter = SoftwrapIterator.init("very-long-word \nworld", canvas);
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("very-l", first.?.bytes);
    try std.testing.expectEqual(6, first.?.width);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings("ong-wo", second.?.bytes);
    try std.testing.expectEqual(6, second.?.width);

    const third = iter.next();
    try std.testing.expect(third != null);
    try std.testing.expectEqualStrings("rd", third.?.bytes);
    try std.testing.expectEqual(2, third.?.width);

    const fourth = iter.next();
    try std.testing.expect(fourth != null);
    try std.testing.expectEqualStrings("world", fourth.?.bytes);
    try std.testing.expectEqual(5, fourth.?.width);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "SoftwrapIterator: soft breaks with leading spaces" {
    const t = @import("test.zig");
    const canvas = try t.createCanvas(std.testing.allocator, 6, 10);
    defer t.destroyCanvas(std.testing.allocator, canvas);
    var iter = SoftwrapIterator.init("Hello,        \n world", canvas);
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello,", first.?.bytes);
    try std.testing.expectEqual(6, first.?.width);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings(" world", second.?.bytes);
    try std.testing.expectEqual(6, second.?.width);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "LineIterator: LF breaks" {
    const input = "Hello, \n world";
    var iter: LineIterator = .{ .buf = input };
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello, ", first.?);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings(" world", second.?);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "LineIterator: CR breaks" {
    const input = "Hello, \r world";
    var iter: LineIterator = .{ .buf = input };
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello, ", first.?);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings(" world", second.?);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "LineIterator: CRLF breaks" {
    const input = "Hello, \r\n world";
    var iter: LineIterator = .{ .buf = input };
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello, ", first.?);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings(" world", second.?);

    const end = iter.next();
    try std.testing.expect(end == null);
}

test "LineIterator: CRLF breaks with empty line" {
    const input = "Hello, \r\n\r\n world";
    var iter: LineIterator = .{ .buf = input };
    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("Hello, ", first.?);

    const second = iter.next();
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings("", second.?);

    const third = iter.next();
    try std.testing.expect(third != null);
    try std.testing.expectEqualStrings(" world", third.?);

    const end = iter.next();
    try std.testing.expect(end == null);
}
