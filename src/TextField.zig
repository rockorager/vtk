const std = @import("std");
const vaxis = @import("vaxis");

const vtk = @import("main.zig");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Key = vaxis.Key;
const Cell = vaxis.Cell;
const Window = vaxis.Window;
const Unicode = vaxis.Unicode;

const TextField = @This();

const ellipsis: Cell.Character = .{ .grapheme = "…", .width = 1 };

// Index of our cursor
buf: Buffer,

/// the number of graphemes to skip when drawing. Used for horizontal scrolling
draw_offset: usize = 0,
/// the column we placed the cursor the last time we drew
prev_cursor_col: usize = 0,
/// the grapheme index of the cursor the last time we drew
prev_cursor_idx: usize = 0,
/// approximate distance from an edge before we scroll
scroll_offset: usize = 4,

unicode: *const Unicode,

pub fn init(alloc: std.mem.Allocator, unicode: *const Unicode) TextField {
    return TextField{
        .buf = Buffer.init(alloc),
        .unicode = unicode,
    };
}

pub fn deinit(self: *TextField) void {
    self.buf.deinit();
}

pub fn widget(self: *TextField) vtk.Widget {
    return .{
        .userdata = self,
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, event: vtk.Event) ?vtk.Command {
    const self: *TextField = @ptrCast(@alignCast(ptr));
    return self.handleEvent(event);
}

pub fn handleEvent(self: *TextField, event: vtk.Event) ?vtk.Command {
    switch (event) {
        .focus_out, .focus_in => return .redraw,
        .key_press => |key| {
            if (key.matches(Key.backspace, .{})) {
                self.deleteBeforeCursor();
                return vtk.consumeAndRedraw();
            } else if (key.matches(Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
                self.deleteAfterCursor();
                return vtk.consumeAndRedraw();
            } else if (key.matches(Key.left, .{}) or key.matches('b', .{ .ctrl = true })) {
                self.cursorLeft();
                return vtk.consumeAndRedraw();
            } else if (key.matches(Key.right, .{}) or key.matches('f', .{ .ctrl = true })) {
                self.cursorRight();
                return vtk.consumeAndRedraw();
            } else if (key.matches('a', .{ .ctrl = true }) or key.matches(Key.home, .{})) {
                self.buf.moveGapLeft(self.buf.firstHalf().len);
                return vtk.consumeAndRedraw();
            } else if (key.matches('e', .{ .ctrl = true }) or key.matches(Key.end, .{})) {
                self.buf.moveGapRight(self.buf.secondHalf().len);
                return vtk.consumeAndRedraw();
            } else if (key.matches('k', .{ .ctrl = true })) {
                self.deleteToEnd();
                return vtk.consumeAndRedraw();
            } else if (key.matches('u', .{ .ctrl = true })) {
                self.deleteToStart();
                return vtk.consumeAndRedraw();
            } else if (key.matches('b', .{ .alt = true }) or key.matches(Key.left, .{ .alt = true })) {
                self.moveBackwardWordwise();
                return vtk.consumeAndRedraw();
            } else if (key.matches('f', .{ .alt = true }) or key.matches(Key.right, .{ .alt = true })) {
                self.moveForwardWordwise();
                return vtk.consumeAndRedraw();
            } else if (key.matches('w', .{ .ctrl = true }) or key.matches(Key.backspace, .{ .alt = true })) {
                self.deleteWordBefore();
                return vtk.consumeAndRedraw();
            } else if (key.matches('d', .{ .alt = true })) {
                self.deleteWordAfter();
                return vtk.consumeAndRedraw();
            } else if (key.text) |text| {
                self.insertSliceAtCursor(text) catch |err| {
                    std.log.err("Couldn't insert char: {}", .{err});
                };
                return vtk.consumeAndRedraw();
            }
        },
        else => {},
    }
    return null;
}

/// insert text at the cursor position
pub fn insertSliceAtCursor(self: *TextField, data: []const u8) std.mem.Allocator.Error!void {
    var iter = self.unicode.graphemeIterator(data);
    while (iter.next()) |text| {
        try self.buf.insertSliceAtCursor(text.bytes(data));
    }
}

pub fn sliceToCursor(self: *TextField, buf: []u8) []const u8 {
    assert(buf.len >= self.buf.cursor);
    @memcpy(buf[0..self.buf.cursor], self.buf.firstHalf());
    return buf[0..self.buf.cursor];
}

/// calculates the display width from the draw_offset to the cursor
pub fn widthToCursor(self: *TextField, ctx: vtk.DrawContext) usize {
    var width: usize = 0;
    const first_half = self.buf.firstHalf();
    var first_iter = self.unicode.graphemeIterator(first_half);
    var i: usize = 0;
    while (first_iter.next()) |grapheme| {
        defer i += 1;
        if (i < self.draw_offset) {
            continue;
        }
        const g = grapheme.bytes(first_half);
        width += ctx.stringWidth(g);
    }
    return width;
}

pub fn cursorLeft(self: *TextField) void {
    // We need to find the size of the last grapheme in the first half
    var iter = self.unicode.graphemeIterator(self.buf.firstHalf());
    var len: usize = 0;
    while (iter.next()) |grapheme| {
        len = grapheme.len;
    }
    self.buf.moveGapLeft(len);
}

pub fn cursorRight(self: *TextField) void {
    var iter = self.unicode.graphemeIterator(self.buf.secondHalf());
    const grapheme = iter.next() orelse return;
    self.buf.moveGapRight(grapheme.len);
}

pub fn graphemesBeforeCursor(self: *const TextField) usize {
    const first_half = self.buf.firstHalf();
    var first_iter = self.unicode.graphemeIterator(first_half);
    var i: usize = 0;
    while (first_iter.next()) |_| {
        i += 1;
    }
    return i;
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    const self: *TextField = @ptrCast(@alignCast(ptr));
    return self.draw(ctx);
}

pub fn draw(self: *TextField, ctx: vtk.DrawContext) Allocator.Error!vtk.Surface {
    // Create a surface with max width and a minimum height of 1.
    var surface = try vtk.Surface.init(
        ctx.arena,
        self.widget(),
        .{ .width = ctx.max.width, .height = @max(ctx.min.height, 1) },
    );
    surface.focusable = true;
    surface.handles_mouse = true;

    const base: vaxis.Cell = .{ .style = .{} };
    @memset(surface.buffer, base);
    const style: vaxis.Style = .{};
    const cursor_idx = self.graphemesBeforeCursor();
    if (cursor_idx < self.draw_offset) self.draw_offset = cursor_idx;
    if (ctx.max.width == 0) return surface;
    while (true) {
        const width = self.widthToCursor(ctx);
        if (width >= ctx.max.width) {
            self.draw_offset +|= width - ctx.max.width + 1;
            continue;
        } else break;
    }

    self.prev_cursor_idx = cursor_idx;
    self.prev_cursor_col = 0;

    const first_half = self.buf.firstHalf();
    var first_iter = self.unicode.graphemeIterator(first_half);
    var col: usize = 0;
    var i: usize = 0;
    while (first_iter.next()) |grapheme| {
        if (i < self.draw_offset) {
            i += 1;
            continue;
        }
        const g = grapheme.bytes(first_half);
        const w: u8 = @intCast(ctx.stringWidth(g));
        if (col + w >= ctx.max.width) {
            surface.writeCell(ctx.max.width - 1, 0, .{
                .char = ellipsis,
                .style = style,
            });
            break;
        }
        surface.writeCell(@intCast(col), 0, .{
            .char = .{
                .grapheme = g,
                .width = w,
            },
            .style = style,
        });
        col += w;
        i += 1;
        if (i == cursor_idx) self.prev_cursor_col = col;
    }
    const second_half = self.buf.secondHalf();
    var second_iter = self.unicode.graphemeIterator(second_half);
    while (second_iter.next()) |grapheme| {
        if (i < self.draw_offset) {
            i += 1;
            continue;
        }
        const g = grapheme.bytes(second_half);
        const w: u8 = @intCast(ctx.stringWidth(g));
        if (col + w > ctx.max.width) {
            surface.writeCell(ctx.max.width - 1, 0, .{
                .char = ellipsis,
                .style = style,
            });
            break;
        }
        surface.writeCell(@intCast(col), 0, .{
            .char = .{
                .grapheme = g,
                .width = w,
            },
            .style = style,
        });
        col += w;
        i += 1;
        if (i == cursor_idx) self.prev_cursor_col = col;
    }
    if (self.draw_offset > 0) {
        surface.writeCell(0, 0, .{
            .char = ellipsis,
            .style = style,
        });
    }
    surface.cursor = .{ .col = @intCast(self.prev_cursor_col), .row = 0 };
    return surface;
    // win.showCursor(self.prev_cursor_col, 0);
}

pub fn clearAndFree(self: *TextField) void {
    self.buf.clearAndFree();
    self.reset();
}

pub fn clearRetainingCapacity(self: *TextField) void {
    self.buf.clearRetainingCapacity();
    self.reset();
}

pub fn toOwnedSlice(self: *TextField) ![]const u8 {
    defer self.reset();
    return self.buf.toOwnedSlice();
}

pub fn reset(self: *TextField) void {
    self.draw_offset = 0;
    self.prev_cursor_col = 0;
    self.prev_cursor_idx = 0;
}

// returns the number of bytes before the cursor
pub fn byteOffsetToCursor(self: TextField) usize {
    return self.buf.cursor;
}

pub fn deleteToEnd(self: *TextField) void {
    self.buf.growGapRight(self.buf.secondHalf().len);
}

pub fn deleteToStart(self: *TextField) void {
    self.buf.growGapLeft(self.buf.cursor);
}

pub fn deleteBeforeCursor(self: *TextField) void {
    // We need to find the size of the last grapheme in the first half
    var iter = self.unicode.graphemeIterator(self.buf.firstHalf());
    var len: usize = 0;
    while (iter.next()) |grapheme| {
        len = grapheme.len;
    }
    self.buf.growGapLeft(len);
}

pub fn deleteAfterCursor(self: *TextField) void {
    var iter = self.unicode.graphemeIterator(self.buf.secondHalf());
    const grapheme = iter.next() orelse return;
    self.buf.growGapRight(grapheme.len);
}

/// Moves the cursor backward by words. If the character before the cursor is a space, the cursor is
/// positioned just after the next previous space
pub fn moveBackwardWordwise(self: *TextField) void {
    const trimmed = std.mem.trimRight(u8, self.buf.firstHalf(), " ");
    const idx = if (std.mem.lastIndexOfScalar(u8, trimmed, ' ')) |last|
        last + 1
    else
        0;
    self.buf.moveGapLeft(self.buf.cursor - idx);
}

pub fn moveForwardWordwise(self: *TextField) void {
    const second_half = self.buf.secondHalf();
    var i: usize = 0;
    while (i < second_half.len and second_half[i] == ' ') : (i += 1) {}
    const idx = std.mem.indexOfScalarPos(u8, second_half, i, ' ') orelse second_half.len;
    self.buf.moveGapRight(idx);
}

pub fn deleteWordBefore(self: *TextField) void {
    // Store current cursor position. Move one word backward. Delete after the cursor the bytes we
    // moved
    const pre = self.buf.cursor;
    self.moveBackwardWordwise();
    self.buf.growGapRight(pre - self.buf.cursor);
}

pub fn deleteWordAfter(self: *TextField) void {
    // Store current cursor position. Move one word backward. Delete after the cursor the bytes we
    // moved
    const second_half = self.buf.secondHalf();
    var i: usize = 0;
    while (i < second_half.len and second_half[i] == ' ') : (i += 1) {}
    const idx = std.mem.indexOfScalarPos(u8, second_half, i, ' ') orelse second_half.len;
    self.buf.growGapRight(idx);
}

test "assertion" {
    const alloc = std.testing.allocator_instance.allocator();
    const unicode = try Unicode.init(alloc);
    defer unicode.deinit();
    const astronaut = "👩‍🚀";
    const astronaut_emoji: Key = .{
        .text = astronaut,
        .codepoint = try std.unicode.utf8Decode(astronaut[0..4]),
    };
    var input = TextField.init(std.testing.allocator, &unicode);
    defer input.deinit();
    for (0..6) |_| {
        _ = input.handleEvent(.{ .key_press = astronaut_emoji });
    }
}

test "sliceToCursor" {
    const alloc = std.testing.allocator_instance.allocator();
    const unicode = try Unicode.init(alloc);
    defer unicode.deinit();
    var input = init(alloc, &unicode);
    defer input.deinit();
    try input.insertSliceAtCursor("hello, world");
    input.cursorLeft();
    input.cursorLeft();
    input.cursorLeft();
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("hello, wo", input.sliceToCursor(&buf));
    input.cursorRight();
    try std.testing.expectEqualStrings("hello, wor", input.sliceToCursor(&buf));
}

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    cursor: usize,
    gap_size: usize,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{
            .allocator = allocator,
            .buffer = &.{},
            .cursor = 0,
            .gap_size = 0,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.buffer);
    }

    pub fn firstHalf(self: Buffer) []const u8 {
        return self.buffer[0..self.cursor];
    }

    pub fn secondHalf(self: Buffer) []const u8 {
        return self.buffer[self.cursor + self.gap_size ..];
    }

    pub fn grow(self: *Buffer, n: usize) std.mem.Allocator.Error!void {
        // Always grow by 512 bytes
        const new_size = self.buffer.len + n + 512;
        // Allocate the new memory
        const new_memory = try self.allocator.alloc(u8, new_size);
        // Copy the first half
        @memcpy(new_memory[0..self.cursor], self.firstHalf());
        // Copy the second half
        const second_half = self.secondHalf();
        @memcpy(new_memory[new_size - second_half.len ..], second_half);
        self.allocator.free(self.buffer);
        self.buffer = new_memory;
        self.gap_size = new_size - second_half.len - self.cursor;
    }

    pub fn insertSliceAtCursor(self: *Buffer, slice: []const u8) std.mem.Allocator.Error!void {
        if (slice.len == 0) return;
        if (self.gap_size <= slice.len) try self.grow(slice.len);
        @memcpy(self.buffer[self.cursor .. self.cursor + slice.len], slice);
        self.cursor += slice.len;
        self.gap_size -= slice.len;
    }

    /// Move the gap n bytes to the left
    pub fn moveGapLeft(self: *Buffer, n: usize) void {
        const new_idx = self.cursor -| n;
        const dst = self.buffer[new_idx + self.gap_size ..];
        const src = self.buffer[new_idx..self.cursor];
        std.mem.copyForwards(u8, dst, src);
        self.cursor = new_idx;
    }

    pub fn moveGapRight(self: *Buffer, n: usize) void {
        const new_idx = self.cursor + n;
        const dst = self.buffer[self.cursor..];
        const src = self.buffer[self.cursor + self.gap_size .. new_idx + self.gap_size];
        std.mem.copyForwards(u8, dst, src);
        self.cursor = new_idx;
    }

    /// grow the gap by moving the cursor n bytes to the left
    pub fn growGapLeft(self: *Buffer, n: usize) void {
        // gap grows by the delta
        self.gap_size += n;
        self.cursor -|= n;
    }

    /// grow the gap by removing n bytes after the cursor
    pub fn growGapRight(self: *Buffer, n: usize) void {
        self.gap_size = @min(self.gap_size + n, self.buffer.len - self.cursor);
    }

    pub fn clearAndFree(self: *Buffer) void {
        self.cursor = 0;
        self.allocator.free(self.buffer);
        self.buffer = &.{};
        self.gap_size = 0;
    }

    pub fn clearRetainingCapacity(self: *Buffer) void {
        self.cursor = 0;
        self.gap_size = self.buffer.len;
    }

    pub fn toOwnedSlice(self: *Buffer) std.mem.Allocator.Error![]const u8 {
        const first_half = self.firstHalf();
        const second_half = self.secondHalf();
        const buf = try self.allocator.alloc(u8, first_half.len + second_half.len);
        @memcpy(buf[0..first_half.len], first_half);
        @memcpy(buf[first_half.len..], second_half);
        self.clearAndFree();
        return buf;
    }

    pub fn realLength(self: *const Buffer) usize {
        return self.firstHalf().len + self.secondHalf().len;
    }
};

test "TextInput.zig: Buffer" {
    var gap_buf = Buffer.init(std.testing.allocator);
    defer gap_buf.deinit();

    try gap_buf.insertSliceAtCursor("abc");
    try std.testing.expectEqualStrings("abc", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("", gap_buf.secondHalf());

    gap_buf.moveGapLeft(1);
    try std.testing.expectEqualStrings("ab", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("c", gap_buf.secondHalf());

    try gap_buf.insertSliceAtCursor(" ");
    try std.testing.expectEqualStrings("ab ", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("c", gap_buf.secondHalf());

    gap_buf.growGapLeft(1);
    try std.testing.expectEqualStrings("ab", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("c", gap_buf.secondHalf());
    try std.testing.expectEqual(2, gap_buf.cursor);

    gap_buf.growGapRight(1);
    try std.testing.expectEqualStrings("ab", gap_buf.firstHalf());
    try std.testing.expectEqualStrings("", gap_buf.secondHalf());
    try std.testing.expectEqual(2, gap_buf.cursor);
}

test "TextField satisfies widget interface" {
    var text: TextField = undefined;
    _ = text.widget();
}
