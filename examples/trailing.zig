const std = @import("std");
const zdap = @import("zdap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const options = zdap.Parser.parse(Flags, "trailing", args, .{});

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

const Flags = struct {
    some_flag: bool,

    @"--": struct {
        some_number: i32,
        maybe_number: ?i32,

        // The specially named '...' positional field can be used to collect the remaining
        // positional arguments after all others have been parsed.
        //
        // Any argument after the first trailing positional argument will be included here, and
        // will not be parsed as a flag or command, even if it matches one, so having both a
        // trailing positional field and a command field is redundant.
        @"...": []const []const u8,
    },
};
