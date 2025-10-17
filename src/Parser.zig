pub const Options = struct {
    skip_first_arg: bool = true,
    /// Terminal colors used when printing help and error messages. A default theme is provided.
    /// To disable colors completely, pass an empty colorscheme: `&.{}`.
    colors: *const ColorScheme = &.default,
};

arg_it: zdap.ArgumentsIterator,
colors: *const ColorScheme,

pub fn parse(
    comptime Flags: type,
    /// The name of your program.
    comptime exe_name: []const u8,
    args: []const [:0]const u8,
    options: Options,
) Flags {
    var parser = Parser{
        .arg_it = .init(args, options.skip_first_arg),
        .colors = options.colors,
    };

    return parser.innerParse(Flags, exe_name);
}

pub fn parseValue(comptime T: type, it: *zdap.ArgumentsIterator, colors: zdap.ColorScheme, value: []const u8) T {
    if (T == []const u8 or T == [:0]const u8) return value;

    switch (@typeInfo(T)) {
        .int => |info| return std.fmt.parseInt(T, value, 0) catch |err| {
            switch (err) {
                error.Overflow => zdap.fatal(
                    colors,
                    "value out of bounds for {d}-bit {s} integer: {s}",
                    .{ info.bits, @tagName(info.signedness), value },
                ),
                error.InvalidCharacter => zdap.fatal(
                    colors,
                    "expected integer number, found '{s}'",
                    .{value},
                ),
            }
        },
        .float => return std.fmt.parseFloat(T, value) catch |err| switch (err) {
            error.InvalidCharacter => zdap.fatal(colors, "expected numerical value, found '{s}'", .{value}),
        },
        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, value, meta.toKebab(field.name))) {
                    return @enumFromInt(field.value);
                }
            }

            zdap.fatal(colors, "unrecognized option: '{s}'", .{value});
        },
        .@"struct" => |s| {
            it.current -= 1;

            if (@hasDecl(T, meta.special_fields.zdap_parse)) {
                return @field(T, meta.special_fields.zdap_parse)(it, colors) catch |err| switch (err) {
                    error.MissingArgument => zdap.fatal(colors, "missing argument for type '{s}'", .{@typeName(T)}),
                    else => zdap.fatal(colors, "could not parse value of type '{s}': {t}", .{ @typeName(T), err }),
                };
            } else {
                var st: T = undefined;

                inline for (s.fields) |f| {
                    const next = it.next() orelse zdap.fatal(colors, "missing value '{s}' for compound", .{f.name});
                    @field(st, f.name) = parseValue(f.type, it, colors, next);
                }

                return st;
            }
        },
        else => comptime meta.compileError("invalid type: {s}", .{@typeName(T)}),
    }
}

fn innerParse(parser: *Parser, comptime Flags: type, comptime command_name: []const u8) Flags {
    const info = comptime meta.info(Flags);
    const help = comptime Help.generate(Flags, info, command_name);

    var flags: Flags = undefined;
    var seen: std.enums.EnumFieldStruct(std.meta.FieldEnum(Flags), bool, false) = .{};

    if (comptime meta.hasTrailingField(Flags)) @field(@field(flags, meta.special_fields.positional), meta.special_fields.trailing) = &.{};

    // The index from the first argument we parsed.
    var index: usize = 0;

    // The index of the next positional field to be parsed.
    var positional_index: usize = 0;

    next_arg: while (parser.arg_it.next()) |arg| {
        defer index += 1;
        if (arg.len == 0) zdap.fatal(parser.colors.*, "empty argument", .{});

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
                if (index > 0) zdap.fatal(parser.colors.*, "unexpected subcommand", .{});

                const cmd_flags = parser.innerParse(cmd.type, command_name ++ " " ++ cmd.command_name);
                const selected_subcommand = &@field(flags, meta.special_fields.subcommand);

                selected_subcommand.* = @unionInit(meta.Unwrap(@TypeOf(selected_subcommand.*)), cmd.field_name, cmd_flags);

                @field(seen, meta.special_fields.subcommand) = true;
                std.debug.assert(parser.arg_it.next() == null); // Subcommands must parse all remaining arguments
                break :next_arg;
            }
        }

        if (std.mem.eql(u8, arg, "--")) {
            // Blindly treat remaining arguments as positional.
            while (parser.arg_it.next()) |positional| {
                if (!comptime meta.hasPositionals(Flags)) zdap.fatal(parser.colors.*, "unexpected argument: {s}", .{positional});

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
                const seen_flag = &@field(seen, flag.field_name);
                parser.storeFlag(Flags, flag, &flags, seen_flag.*);
                seen_flag.* = true;
                continue :next_arg;
            };

            zdap.fatal(parser.colors.*, "unrecognized flag: {s}", .{arg});
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            if (arg.len == 1) zdap.fatal(parser.colors.*, "unrecognized argument: '-'", .{});

            const switch_set = arg[1..];
            next_switch: for (switch_set, 0..) |ch, i| {
                inline for (info.flags) |flag| if (flag.switch_char) |switch_char| {
                    if (ch == switch_char) {
                        // Removing this check would allow formats like:
                        // `$ <cmd> -abc value-for-a value-for-b value-for-c`
                        if (flag.type != bool and i < switch_set.len - 1) zdap.fatal(parser.colors.*, "missing value after switch: {c}", .{switch_char});

                        const seen_flag = &@field(seen, flag.field_name);
                        parser.storeFlag(Flags, flag, &flags, seen_flag.*);
                        seen_flag.* = true;
                        continue :next_switch;
                    }
                };

                zdap.fatal(parser.colors.*, "unrecognized switch: {c}", .{ch});
            }

            continue :next_arg;
        }

        if (comptime meta.hasPositionals(Flags)) {
            const positionals = &@field(flags, meta.special_fields.positional);

            if (parser.parsePositional(arg, positional_index, info.positionals, positionals) == .consumed_all) {
                break :next_arg;
            }

            positional_index += 1;
            continue;
        }

        zdap.fatal(parser.colors.*, "unexpected argument: {s}", .{arg});
    }

    if (info.subcommands.len > 0 and !@field(seen, meta.special_fields.subcommand)) {
        if (!info.optional_subcommands) {
            zdap.fatal(parser.colors.*, "missing required subcommand", .{});
        } else @field(flags, meta.special_fields.subcommand) = null;
    }

    inline for (info.flags) |flag| if (!@field(seen, flag.field_name)) {
        @field(flags, flag.field_name) = meta.defaultValue(flag) orelse
            switch (@typeInfo(flag.type)) {
                .bool => false,
                .optional => null,
                else => zdap.fatal(parser.colors.*, "missing required flag: {s}", .{flag.flag_name}),
            };
    };

    inline for (info.positionals, 0..) |pos, i| {
        if (i >= positional_index) {
            @field(flags.@"--", pos.field_name) = meta.defaultValue(pos) orelse
                switch (@typeInfo(pos.type)) {
                    .optional => null,
                    else => zdap.fatal(parser.colors.*, "missing required argument: {s}", .{pos.arg_name}),
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
            parser.arg_it.current -= 1;
            @field(positionals.*, meta.special_fields.trailing) = parser.arg_it.consumeRemaining();
            return .consumed_all;
        }

        zdap.fatal(parser.colors.*, "unexpected argument: {s}", .{arg});
    }

    switch (index) {
        inline 0...positionals_info.len - 1 => |i| {
            const positional = positionals_info[i];
            const T = meta.Unwrap(positional.type);
            @field(positionals, positional.field_name) = parseValue(T, &parser.arg_it, parser.colors.*, arg);
            return .consumed_one;
        },

        else => unreachable,
    }
}

fn storeFlag(parser: *Parser, comptime Flags: type, comptime flag: meta.Flag, flags: *Flags, seen: bool) void {
    if (flag.type == bool) {
        @field(flags, flag.field_name) = true;
        return;
    }

    const arg = parser.arg_it.next() orelse zdap.fatal(parser.colors.*, "missing value for '{s}'", .{flag.flag_name});

    if (comptime meta.BoundedArrayChild(flag.type)) |T| {
        const bounded: *flag.type = &@field(flags, flag.field_name);

        const item = parseValue(comptime meta.Unwrap(T), &parser.arg_it, parser.colors.*, arg);

        if (seen) {
            if (bounded.len == bounded.capacity()) zdap.fatal(parser.colors.*, "too many values for '{s}'", .{flag.flag_name});
            bounded.appendAssumeCapacity(item);
        } else bounded.* = .initOne(item);
        return;
    }

    if (seen) zdap.fatal(parser.colors.*, "duplicated flag '{s}'", .{flag.flag_name});
    @field(flags, flag.field_name) = parseValue(comptime meta.Unwrap(flag.type), &parser.arg_it, parser.colors.*, arg);
}

const Parser = @This();

const std = @import("std");
const zdap = @import("zdap");
const meta = zdap.meta;

const ColorScheme = zdap.ColorScheme;
const Help = zdap.Help;
const Terminal = zdap.Terminal;
