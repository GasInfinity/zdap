writer: *std.Io.Writer,
config: tty.Config,

pub fn init(config: tty.Config, writer: *std.Io.Writer) Terminal {
    return .{
        .config = config,
        .writer = writer,
    };
}

pub fn print(
    terminal: Terminal,
    style: ColorScheme.Style,
    comptime format: []const u8,
    args: anytype,
) void {
    for (style) |color| {
        terminal.config.setColor(terminal.writer, color) catch {};
    }

    terminal.writer.print(format, args) catch {};

    if (style.len > 0) {
        terminal.config.setColor(terminal.writer, .reset) catch {};
    }
}

const Terminal = @This();

const std = @import("std");
const zdap = @import("zdap");
const ColorScheme = zdap.ColorScheme;

const tty = std.Io.tty;
const File = std.fs.File;
