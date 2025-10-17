const std = @import("std");
const zdap = @import("zdap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const options = zdap.Parser.parse(Flags, "bounded", args, .{});

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stderr().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Files:\n", .{});
    for (options.file.constSlice()) |f| {
        try stdout.print("{}\n", .{f});
    }
    try stdout.flush();
}

const File = struct {
    name: []const u8,
    size: u32,
};

const Flags = struct {
    pub const description =
        \\Support many values for one flag
    ;

    file: zdap.BoundedArray(File, 4),
};
