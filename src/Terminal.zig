const Terminal = @This();

const std = @import("std");
const ColorScheme = @import("ColorScheme.zig");

const tty = std.io.tty;
const File = std.fs.File;

writer: File.Writer,
config: tty.Config,

pub fn init(file: File, buffer: []u8) Terminal {
    return .{
        .writer = file.writerStreaming(buffer),
        .config = .detect(file),
    };
}

pub fn print(
    terminal: *Terminal,
    style: ColorScheme.Style,
    comptime format: []const u8,
    args: anytype,
) void {
    for (style) |color| {
        terminal.config.setColor(&terminal.writer.interface, color) catch {};
    }

    terminal.writer.interface.print(format, args) catch {};

    if (style.len > 0) {
        terminal.config.setColor(&terminal.writer.interface, .reset) catch {};
    }
}

pub fn flush(terminal: *Terminal) void {
    terminal.writer.interface.flush() catch {};
}
