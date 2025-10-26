pub const ArgumentsIterator = struct {
    args: []const [:0]const u8,
    current: usize,

    pub fn init(args: []const [:0]const u8, skip_first: bool) ArgumentsIterator {
        return .{
            .args = args,
            .current = @intFromBool(skip_first),
        };
    }

    pub fn consumeRemaining(it: *ArgumentsIterator) []const [:0]const u8 {
        defer it.current = it.args.len;
        return it.args[it.current..];
    }

    pub fn next(it: *ArgumentsIterator) ?[:0]const u8 {
        if (it.current >= it.args.len) return null;

        defer it.current += 1;
        return it.args[it.current];
    }
};

/// Used to support multiple arguments with the same name, e.g: --file A --file B --file C
pub fn BoundedArray(comptime T: type, comptime n: usize) type {
    return struct {
        pub const empty: Bounded = .{ .buffer = undefined, .len = 0 };

        const Bounded = @This();

        buffer: [n]T,
        len: usize,

        pub fn initOne(item: T) Bounded {
            return .{
                .buffer = .{item} ++ @as([n - 1]T, undefined),
                .len = 1,
            };
        }

        pub fn constSlice(b: *const Bounded) []const T {
            return b.buffer[0..b.len];
        }

        pub fn slice(b: *Bounded) []T {
            return b.buffer[0..b.len];
        }

        pub fn capacity(b: Bounded) usize {
            return b.buffer.len;
        }

        pub fn appendAssumeCapacity(b: *Bounded, item: T) void {
            b.buffer[b.len] = item;
            b.len += 1;
        }
    };
}

pub fn fatal(colors: ColorScheme, help: Help, comptime fmt: []const u8, args: anytype) noreturn {
    var writer_buffer: [256]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&writer_buffer);
    const term = Terminal.init(.detect(std.fs.File.stderr()), &stderr.interface);
    help.usage.render(term, colors);
    term.print(colors.error_label, "Error: ", .{});
    term.print(colors.error_message, fmt ++ "\n", args);
    stderr.interface.flush() catch {};
    std.process.exit(1);
}

const std = @import("std");

pub const ColorScheme = @import("ColorScheme.zig");
pub const Parser = @import("Parser.zig");
pub const Help = @import("Help.zig");
pub const Terminal = @import("Terminal.zig");
pub const meta = @import("meta.zig");
