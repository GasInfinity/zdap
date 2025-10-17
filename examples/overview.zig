const std = @import("std");
const zdap = @import("zdap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const options = zdap.Parser.parse(Flags, "overview", args, .{});

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
    // Optional description of the program / subcommand.
    pub const description =
        \\This is a dummy command for testing purposes.
        \\There are a bunch of options for demonstration purposes.
    ;

    // Optional description of some or all of the flags (must match field names in the struct).
    pub const descriptions = .{
        .version = "Print out some top-level version",
        .size = "Spice-up the version?",
    };

    // Optional declaration to define shorthands. These can be chained e.g '-vs large'.
    pub const switches = .{
        .version = 'v',
    };

    version: bool, // Set to `true` only if '--force' is passed.

    size: enum {
        small,
        medium,
        large,

        // Displayed in the '--help' message.
        pub const descriptions = .{
            .small = "The least big",
            .medium = "Not quite small, not quite big",
            .large = "The biggest",
        };
    } = .small,

    // Subcommands can be defined through the `-` special field, which should be a tagged union
    // or an optional tagged union (for subcommands that are not required).
    //
    // Positionals and subcommands cannot be used at the same time due to its ambiguous nature.
    // Flags and Non-optional subcommands cannot be used at the same time for the same reason.
    //
    // Optional subcommands can only be used with optional flags.
    @"-": ?union(enum) {
        frobnicate: struct {
            // Optional description of the program / subcommand.
            pub const description = "Frobnicate everywhere";

            pub const descriptions = .{
                .level = "Frobnication level",
            };

            level: u8,

            // The `--` field is a special field that defines arguments that are not associated
            // with any --flag, thus being positional arguments.
            @"--": struct {
                // The `...` field is another special field for capturing all remaining trailing positionals.
                @"...": []const []const u8,
            },
        },
        defrabulise: struct {
            pub const description = "Defrabulise everyone";

            supercharge: bool,
        },
    },
};
