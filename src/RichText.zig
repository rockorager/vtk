const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const Allocator = std.mem.Allocator;

const RichText = @This();

pub const TextSpan = struct {
    text: []const u8,
    style: vaxis.Style = .{},
};

text: []const TextSpan,
text_align: enum { left, center, right } = .left,
base_style: vaxis.Style = .{},
softwrap: bool = true,
overflow: enum { ellipsis, clip } = .ellipsis,
width_basis: enum { parent, longest_line } = .longest_line,

pub fn widget(self: *const RichText) vtk.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = vtk.noopEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *const RichText = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *const RichText, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    var iter = try SoftwrapIterator.init(self.text, ctx);
    const container_size = switch (self.width_basis) {
        .parent => ctx.max,
        .longest_line => self.findContainerSize(&iter),
    };

    // Create a surface of target width and max height. We'll trim the result after drawing
    const surface = try vtk.Surface.init(
        ctx.arena,
        self.widget(),
        container_size,
    );
    const base: vaxis.Cell = .{ .style = self.base_style };
    @memset(surface.buffer, base);

    var row: u16 = 0;
    if (self.softwrap) {
        while (iter.next()) |line| {
            if (row >= ctx.max.height) break;
            defer row += 1;
            var col: u16 = switch (self.text_align) {
                .left => 0,
                .center => (container_size.width - line.width) / 2,
                .right => container_size.width - line.width,
            };
            for (line.cells) |cell| {
                surface.writeCell(col, row, cell);
                col += cell.char.width;
            }
        }
    } else {
        while (iter.nextHardBreak()) |line| {
            if (row >= ctx.max.height) break;
            const line_width = blk: {
                var w: u16 = 0;
                for (line) |cell| {
                    w +|= cell.char.width;
                }
                break :blk w;
            };
            defer row += 1;
            var col: u16 = switch (self.text_align) {
                .left => 0,
                .center => (container_size.width -| line_width) / 2,
                .right => container_size.width -| line_width,
            };
            for (line) |cell| {
                if (col + cell.char.width >= iter.ctx.max.width and
                    line_width > iter.ctx.max.width and
                    self.overflow == .ellipsis)
                {
                    surface.writeCell(col, row, .{
                        .char = .{ .grapheme = "…", .width = 1 },
                    });
                    col = ctx.max.width;
                    continue;
                } else {
                    surface.writeCell(col, row, cell);
                    col += @intCast(cell.char.width);
                }
            }
        }
    }
    return surface.trimHeight(@max(row, ctx.min.height));
}

/// Finds the widest line within the viewable portion of ctx
fn findContainerSize(self: RichText, iter: *SoftwrapIterator) vtk.Size {
    defer iter.reset();
    var row: u16 = 0;
    var max_width: u16 = iter.ctx.min.width;
    if (self.softwrap) {
        while (iter.next()) |line| {
            if (row >= iter.ctx.max.height) break;
            defer row += 1;
            max_width = @max(max_width, line.width);
        }
    } else {
        while (iter.nextHardBreak()) |line| {
            if (row >= iter.ctx.max.height) break;
            defer row += 1;
            var w: u16 = 0;
            for (line) |cell| {
                w +|= cell.char.width;
            }
            max_width = @max(max_width, w);
        }
    }
    const result_width = @min(iter.ctx.max.width, max_width);
    return .{ .width = result_width, .height = @max(row, iter.ctx.min.height) };
}

pub const SoftwrapIterator = struct {
    arena: std.heap.ArenaAllocator,
    ctx: vtk.DrawContext,
    text: []const vaxis.Cell,
    line: []const vaxis.Cell,
    index: usize = 0,
    // Index of the hard iterator
    hard_index: usize = 0,

    const soft_breaks = " \t";

    pub const Line = struct {
        width: u16,
        cells: []const vaxis.Cell,
    };

    fn init(spans: []const TextSpan, ctx: vtk.DrawContext) Allocator.Error!SoftwrapIterator {
        // Estimate the number of cells we need
        var len: usize = 0;
        for (spans) |span| {
            len += span.text.len;
        }
        var arena = std.heap.ArenaAllocator.init(ctx.arena);
        var list = try std.ArrayList(vaxis.Cell).initCapacity(arena.allocator(), len);

        for (spans) |span| {
            var iter = ctx.graphemeIterator(span.text);
            while (iter.next()) |grapheme| {
                const char = grapheme.bytes(span.text);
                const width = ctx.stringWidth(char);
                const cell: vaxis.Cell = .{
                    .char = .{ .grapheme = char, .width = @intCast(width) },
                    .style = span.style,
                };
                try list.append(cell);
            }
        }
        return .{
            .arena = arena,
            .ctx = ctx,
            .text = list.items,
            .line = &.{},
        };
    }

    fn reset(self: *SoftwrapIterator) void {
        self.index = 0;
        self.hard_index = 0;
        self.line = &.{};
    }

    fn deinit(self: *SoftwrapIterator) void {
        self.arena.deinit();
    }

    fn nextHardBreak(self: *SoftwrapIterator) ?[]const vaxis.Cell {
        if (self.hard_index >= self.text.len) return null;
        const start = self.hard_index;
        var saw_cr: bool = false;
        while (self.hard_index < self.text.len) : (self.hard_index += 1) {
            const cell = self.text[self.hard_index];
            if (std.mem.eql(u8, cell.char.grapheme, "\r")) {
                saw_cr = true;
            }
            if (std.mem.eql(u8, cell.char.grapheme, "\n")) {
                self.hard_index += 1;
                if (saw_cr) {
                    return self.text[start .. self.hard_index - 2];
                }
                return self.text[start .. self.hard_index - 1];
            }
            if (saw_cr) {
                // back up one
                self.hard_index -= 1;
                return self.text[start .. self.hard_index - 1];
            }
        } else return self.text[start..];
    }

    fn trimWSPRight(text: []const vaxis.Cell) []const vaxis.Cell {
        // trim linear whitespace
        var i: usize = text.len;
        while (i > 0) : (i -= 1) {
            if (std.mem.eql(u8, text[i - 1].char.grapheme, " ") or
                std.mem.eql(u8, text[i - 1].char.grapheme, "\t"))
            {
                continue;
            }
            break;
        }
        return text[0..i];
    }

    fn trimWSPLeft(text: []const vaxis.Cell) []const vaxis.Cell {
        // trim linear whitespace
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            if (std.mem.eql(u8, text[i].char.grapheme, " ") or
                std.mem.eql(u8, text[i].char.grapheme, "\t"))
            {
                continue;
            }
            break;
        }
        return text[i..];
    }

    fn next(self: *SoftwrapIterator) ?Line {
        // Advance the hard iterator
        if (self.index == self.line.len) {
            self.line = self.nextHardBreak() orelse return null;
            // trim linear whitespace
            self.line = trimWSPRight(self.line);
            self.index = 0;
        }

        const start = self.index;
        var cur_width: u16 = 0;
        while (self.index < self.line.len) {
            // Find the width from current position to next word break
            const idx = self.nextWrap();
            const word = self.line[self.index..idx];
            const next_width = blk: {
                var w: usize = 0;
                for (word) |ch| {
                    w += ch.char.width;
                }
                break :blk w;
            };

            if (cur_width + next_width > self.ctx.max.width) {
                // Trim the word to see if it can fit on a line by itself
                const trimmed = trimWSPLeft(word);
                const trimmed_width = next_width - trimmed.len;
                if (trimmed_width > self.ctx.max.width) {
                    // Won't fit on line by itself, so fit as much on this line as we can
                    for (word) |cell| {
                        if (cur_width + cell.char.width > self.ctx.max.width) {
                            const end = self.index;
                            return .{ .width = cur_width, .cells = self.line[start..end] };
                        }
                        cur_width += @intCast(cell.char.width);
                        self.index += 1;
                    }
                }
                const end = self.index;
                // We are softwrapping, advance index to the start of the next word. This is equal
                // to the difference in our word length and trimmed word length
                self.index += (word.len - trimmed.len);
                return .{ .width = cur_width, .cells = self.line[start..end] };
            }

            self.index = idx;
            cur_width += @intCast(next_width);
        }
        return .{ .width = cur_width, .cells = self.line[start..] };
    }

    fn nextWrap(self: *SoftwrapIterator) usize {
        var i: usize = self.index;

        // Find the first non-whitespace character
        while (i < self.line.len) : (i += 1) {
            if (std.mem.eql(u8, self.line[i].char.grapheme, " ") or
                std.mem.eql(u8, self.line[i].char.grapheme, "\t"))
            {
                continue;
            }
            break;
        }

        // Now find the first whitespace
        while (i < self.line.len) : (i += 1) {
            if (std.mem.eql(u8, self.line[i].char.grapheme, " ") or
                std.mem.eql(u8, self.line[i].char.grapheme, "\t"))
            {
                return i;
            }
            continue;
        }

        return self.line.len;
    }
};
