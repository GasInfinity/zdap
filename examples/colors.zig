const std = @import("std");
const zdap = @import("zdap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    _ = zdap.Parser.parse(Flags, "colors", args, .{
        // Use the `colors` option to provide a colorscheme for the error/help messages.
        // Specifying this as empty: `.colors = &.{}` will disable colors.
        // Each field is a list of type `std.Io.tty.Color`.
        .colors = &zdap.ColorScheme{
            .error_label = &.{ .bright_red, .bold },
            .command_name = &.{.bright_green},
            .header = &.{ .yellow, .bold },
            .usage = &.{.dim},
        },
    });
}

const Flags = struct {
    pub const description =
        \\Showcase of terminal color options.
    ;

    foo: bool,
    bar: []const u8,
};
