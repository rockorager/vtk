const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

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

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const Text = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *const Text, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const container_width = switch (self.width_basis) {
        .parent => ctx.max.width,
        .longest_line => @min(ctx.max.width, @max(ctx.min.width, self.findWidestLine(ctx))),
    };

    // Create a surface of target width and max height. We'll trim the result after drawing
    const surface = try vtk.Surface.init(
        ctx.arena,
        self.widget(),
        .{ .width = container_width, .height = ctx.max.height },
    );
    const base_style: vaxis.Style = .{
        .fg = self.style.fg,
        .bg = self.style.bg,
        .reverse = self.style.reverse,
    };
    const base: vaxis.Cell = .{ .style = base_style };
    @memset(surface.buffer, base);

    var row: u16 = 0;
    if (self.softwrap) {
        var iter = SoftwrapIterator.init(self.text, ctx);
        while (iter.next()) |line| {
            if (row >= ctx.max.height) break;
            defer row += 1;
            var col: u16 = switch (self.text_align) {
                .left => 0,
                .center => (container_width - line.width) / 2,
                .right => container_width - line.width,
            };
            var char_iter = ctx.graphemeIterator(line.bytes);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(line.bytes);
                const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = grapheme, .width = grapheme_width },
                    .style = self.style,
                });
                col += grapheme_width;
            }
        }
    } else {
        var line_iter: LineIterator = .{ .buf = self.text };
        while (line_iter.next()) |line| {
            if (row >= ctx.max.height) break;
            const line_width = ctx.stringWidth(line);
            defer row += 1;
            const resolved_line_width = @min(ctx.max.width, line_width);
            var col: u16 = switch (self.text_align) {
                .left => 0,
                .center => (ctx.max.width - resolved_line_width) / 2,
                .right => ctx.max.width - resolved_line_width,
            };
            var char_iter = ctx.graphemeIterator(line);
            while (char_iter.next()) |char| {
                if (col >= ctx.max.width) break;
                const grapheme = char.bytes(line);
                const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));

                if (col + grapheme_width >= ctx.max.width and
                    line_width > ctx.max.width and
                    self.overflow == .ellipsis)
                {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = "…", .width = 1 },
                        .style = self.style,
                    });
                    col = ctx.max.width;
                } else {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = grapheme, .width = grapheme_width },
                        .style = self.style,
                    });
                    col += @intCast(grapheme_width);
                }
            }
        }
    }
    return surface.trimHeight(@max(row, ctx.min.height));
}

/// Finds the widest line within the viewable portion of ctx
fn findWidestLine(self: Text, ctx: vtk.DrawContext) u16 {
    if (self.width_basis == .parent) return ctx.max.width;
    var row: u16 = 0;
    var max_width: u16 = 0;
    if (self.softwrap) {
        var iter = SoftwrapIterator.init(self.text, ctx);
        while (iter.next()) |line| {
            if (row >= ctx.max.height) break;
            defer row += 1;
            max_width = @max(max_width, line.width);
        }
    } else {
        var line_iter: LineIterator = .{ .buf = self.text };
        while (line_iter.next()) |line| {
            if (row >= ctx.max.height) break;
            const line_width = ctx.stringWidth(line);
            defer row += 1;
            const resolved_line_width = @min(ctx.max.width, line_width);
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
    ctx: vtk.DrawContext,
    line: []const u8 = "",
    index: usize = 0,
    hard_iter: LineIterator,

    pub const Line = struct {
        width: u16,
        bytes: []const u8,
    };

    const soft_breaks = " \t";

    fn init(buf: []const u8, ctx: vtk.DrawContext) SoftwrapIterator {
        return .{
            .ctx = ctx,
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
            const next_width = self.ctx.stringWidth(word);

            if (cur_width + next_width > self.ctx.max.width) {
                // Trim the word to see if it can fit on a line by itself
                const trimmed = std.mem.trimLeft(u8, word, " \t");
                const trimmed_bytes = word.len - trimmed.len;
                // The number of bytes we trimmed is equal to the reduction in length
                const trimmed_width = next_width - trimmed_bytes;
                if (trimmed_width > self.ctx.max.width) {
                    // Won't fit on line by itself, so fit as much on this line as we can
                    var iter = self.ctx.graphemeIterator(word);
                    while (iter.next()) |item| {
                        const grapheme = item.bytes(word);
                        const w = self.ctx.stringWidth(grapheme);
                        if (cur_width + w > self.ctx.max.width) {
                            const end = self.index;
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
    const unicode = try vaxis.Unicode.init(std.testing.allocator);
    defer unicode.deinit();
    vtk.DrawContext.init(&unicode, .unicode);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ctx: vtk.DrawContext = .{
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = 20, .height = 10 },
        .arena = arena.allocator(),
    };
    var iter = SoftwrapIterator.init("Hello, \n world", ctx);
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
    const unicode = try vaxis.Unicode.init(std.testing.allocator);
    defer unicode.deinit();
    vtk.DrawContext.init(&unicode, .unicode);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ctx: vtk.DrawContext = .{
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = 6, .height = 10 },
        .arena = arena.allocator(),
    };
    var iter = SoftwrapIterator.init("Hello, \nworld", ctx);
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
    const unicode = try vaxis.Unicode.init(std.testing.allocator);
    defer unicode.deinit();
    vtk.DrawContext.init(&unicode, .unicode);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ctx: vtk.DrawContext = .{
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = 6, .height = 10 },
        .arena = arena.allocator(),
    };
    var iter = SoftwrapIterator.init("very-long-word \nworld", ctx);
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
    const unicode = try vaxis.Unicode.init(std.testing.allocator);
    defer unicode.deinit();
    vtk.DrawContext.init(&unicode, .unicode);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ctx: vtk.DrawContext = .{
        .min = .{ .width = 0, .height = 0 },
        .max = .{ .width = 6, .height = 10 },
        .arena = arena.allocator(),
    };
    var iter = SoftwrapIterator.init("Hello,        \n world", ctx);
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

test "Text satisfies widget interface" {
    const text: Text = .{ .text = "test" };
    _ = text.widget();
}
