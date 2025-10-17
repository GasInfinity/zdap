const std = @import("std");
const zdap = @import("zdap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const options = zdap.Parser.parse(Flags, "structs", args, .{});

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stderr().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try std.json.Stringify.value(
        options,
        .{ .whitespace = .indent_2 },
        stdout,
    );
    try stdout.flush();
}

const File = struct {
    pub const Flag = enum {
        r,
        rx,
        rw,
    };

    name: []const u8,
    size: u32,
    flag: Flag,
};

const Flags = struct {
    // Optional description of the program / subcommand.
    pub const description =
        \\Struct parsing example
    ;

    file: File,
};
