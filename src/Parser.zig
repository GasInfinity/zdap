args: []const [:0]const u8,
current_arg: usize,
colors: *const ColorScheme,

fn fatal(parser: *const Parser, comptime fmt: []const u8, args: anytype) noreturn {
    var writer_buffer: [256]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&writer_buffer);
    const term = Terminal.init(.detect(std.fs.File.stderr()), &stderr.interface);
    term.print(parser.colors.error_label, "Error: ", .{});
    term.print(parser.colors.error_message, fmt ++ "\n", args);
    stderr.interface.flush() catch {};
    std.process.exit(1);
}

pub fn parse(parser: *Parser, Flags: type, comptime command_name: []const u8) Flags {
    const info = comptime meta.info(Flags);
    const help = comptime Help.generate(Flags, info, command_name);

    var flags: Flags = undefined;
    var passed: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    if (comptime meta.hasTrailingField(Flags)) {
        @field(@field(flags, meta.special_fields.positional), meta.special_fields.trailing) = &.{};
    }

    // The index from the first argument we parsed.
    var index: usize = 0;

    // The index of the next positional field to be parsed.
    var positional_index: usize = 0;

    next_arg: while (parser.nextArg()) |arg| {
        defer index += 1;
        if (arg.len == 0) parser.fatal("empty argument", .{});

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            var writer_buffer: [256]u8 = undefined;
            var stdout = std.fs.File.stdout().writer(&writer_buffer);
            const term = Terminal.init(.detect(std.fs.File.stdout()), &stdout.interface);
            help.render(term, parser.colors.*);
            stdout.interface.flush() catch {};
            std.process.exit(0);
        }

        inline for (info.subcommands) |cmd| {
            if (std.mem.eql(u8, arg, cmd.command_name)) {
                if(index > 0) parser.fatal("unexpected subcommand", .{});

                const cmd_flags = parser.parse(cmd.type, command_name ++ " " ++ cmd.command_name);
                const selected_subcommand = &@field(flags, meta.special_fields.subcommand);

                selected_subcommand.* = @unionInit(meta.UnwrapOptional(@TypeOf(selected_subcommand.*)), cmd.field_name, cmd_flags);

                @field(passed, meta.special_fields.subcommand) = true;
                std.debug.assert(parser.nextArg() == null); // Subcommands must parse all remaining arguments
                break :next_arg;
            }
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positional.
            while (parser.nextArg()) |positional| {
                if(!comptime meta.hasPositionals(Flags)) {
                    parser.fatal("unexpected argument: {s}", .{positional});
                }

                const positionals = &@field(flags, meta.special_fields.positional);

                if (parser.parsePositional(positional, positional_index, info.positionals, positionals) == .consumed_all) {
                    break :next_arg;
                }

                positional_index += 1;
            }

            break :next_arg;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            inline for (info.flags) |flag| if (std.mem.eql(u8, arg, flag.flag_name)) {
                @field(flags, flag.field_name) = parser.parseOption(flag.type, flag.flag_name);
                @field(passed, flag.field_name) = true;
                continue :next_arg;
            };

            parser.fatal("unrecognized flag: {s}", .{arg});
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) parser.fatal("unrecognized argument: '-'", .{});

            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) {
                            parser.fatal("missing value after switch: {c}", .{switch_char});
                        }
                        @field(flags, flag.field_name) = parser.parseOption(
                            flag.type,
                            &.{ '-', switch_char },
                        );
                        @field(passed, flag.field_name) = true;
                        continue :next_switch;
                    }
                };

                parser.fatal("unrecognized switch: {c}", .{ch});
            }

            continue :next_arg;
        }
        

        if(comptime meta.hasPositionals(Flags)) {
            const positionals = &@field(flags, meta.special_fields.positional);

            if (parser.parsePositional(arg, positional_index, info.positionals, positionals) == .consumed_all) {
                break :next_arg;
            }

            positional_index += 1;
            continue;
        } 

        parser.fatal("unexpected argument: {s}", .{arg});
    }

    if(info.subcommands.len > 0 and !@field(passed, meta.special_fields.subcommand)) {
        if(!info.optional_subcommands) {
            parser.fatal("missing required subcommand", .{});
        } else @field(flags, meta.special_fields.subcommand) = null;
    }

    inline for (info.flags) |flag| if (!@field(passed, flag.field_name)) {
        @field(flags, flag.field_name) = meta.defaultValue(flag) orelse
            switch (@typeInfo(flag.type)) {
                .bool => false,
                .optional => null,
                else => {
                    parser.fatal("missing required flag: {s}", .{flag.flag_name});
                },
            };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= positional_index) {
            @field(flags.@"--", pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                    .optional => null,
                    else => {
                        parser.fatal("missing required argument: {s}", .{pos.arg_name});
                    },
                };
        }
    }

    return flags;
}

fn parsePositional(
    parser: *Parser,
    arg: [:0]const u8,
    index: usize,
    comptime positionals_info: []const meta.Positional,
    positionals: anytype,
) enum { consumed_one, consumed_all } {
    if (index >= positionals_info.len) {
        if (@hasField(@TypeOf(positionals.*), meta.special_fields.trailing)) {
            @field(positionals.*, meta.special_fields.trailing) = parser.args[parser.current_arg - 1 ..];
            parser.current_arg = parser.args.len;
            return .consumed_all;
        }

        parser.fatal("unexpected argument: {s}", .{arg});
    }

    switch (index) {
        inline 0...positionals_info.len - 1 => |i| {
            const positional = positionals_info[i];
            const T = meta.UnwrapOptional(positional.type);
            @field(positionals, positional.field_name) = parser.parseValue(T, arg);
            return .consumed_one;
        },

        else => unreachable,
    }
}

fn parseOption(parser: *Parser, T: type, option_name: []const u8) T {
    if (T == bool) return true;

    const value = parser.nextArg() orelse {
        parser.fatal("missing value for '{s}'", .{option_name});
    };

    return parser.parseValue(meta.UnwrapOptional(T), value);
}

fn parseValue(parser: *const Parser, T: type, arg: [:0]const u8) T {
    if (T == []const u8 or T == [:0]const u8) return arg;

    switch (@typeInfo(T)) {
        .int => |info| return std.fmt.parseInt(T, arg, 10) catch |err| {
            switch (err) {
                error.Overflow => parser.fatal(
                    "value out of bounds for {d}-bit {s} integer: {s}",
                    .{ info.bits, @tagName(info.signedness), arg },
                ),
                error.InvalidCharacter => parser.fatal(
                    "expected integer number, found '{s}'",
                    .{arg},
                ),
            }
        },
        .float => return std.fmt.parseFloat(T, arg) catch |err| switch (err) {
            error.InvalidCharacter => {
                parser.fatal("expected numerical value, found '{s}'", .{arg});
            },
        },
        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, arg, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }

            parser.fatal("unrecognized option: '{s}'", .{arg});
        },
        else => comptime meta.compileError("invalid flag type: {s}", .{@typeName(T)}),
    }
}

fn nextArg(parser: *Parser) ?[:0]const u8 {
    if (parser.current_arg >= parser.args.len) {
        return null;
    }

    parser.current_arg += 1;
    return parser.args[parser.current_arg - 1];
}

const Parser = @This();

const std = @import("std");
const meta = @import("meta.zig");

pub const Help = @import("Help.zig");
pub const ColorScheme = @import("ColorScheme.zig");
pub const Terminal = @import("Terminal.zig");
