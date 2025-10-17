usage: Usage,
description: ?[]const u8,
sections: []const Section,

pub const Usage = struct {
    const max_line_len = 80;

    command: []const u8,
    body: []const u8,

    /// Don't forget to `flush`!
    pub fn render(usage: Usage, term: Terminal, colors: ColorScheme) void {
        term.print(colors.header, "Usage: ", .{});
        term.print(colors.command_name, "{s}", .{usage.command});
        term.print(colors.usage, "{s}\n", .{usage.body});
    }

    pub fn generate(comptime Flags: type, info: meta.FlagsInfo, command: []const u8) Usage {
        var usage: Usage = .{ .command = command, .body = &.{} };
        var line_len = "Usage: ".len + command.len;

        const flag_formats = meta.getFormats(Flags);
        for (info.flags) |flag| {
            var flag_usage: []const u8 = "";

            if (flag.switch_char) |ch| {
                flag_usage = flag_usage ++ std.fmt.comptimePrint("-{c} | ", .{ch});
            }

            flag_usage = flag_usage ++ flag.flag_name;

            const format = @field(flag_formats, flag.field_name) orelse comptime defaultFormat(flag);

            flag_usage = flag_usage ++ (if (format.len > 0) " " ++ format else "");

            if (flag.isOptional()) flag_usage = "[" ++ flag_usage ++ "]";

            usage.add(flag_usage, &line_len);
        }
        usage.add("[-h | --help]", &line_len);

        for (info.positionals) |arg| {
            const arg_usage = if (arg.isOptional())
                std.fmt.comptimePrint("[{s}]", .{arg.arg_name})
            else
                arg.arg_name;

            usage.add(arg_usage, &line_len);
        }

        if (meta.hasTrailingField(Flags)) usage.add("...", &line_len);
        if (info.subcommands.len > 0) usage.add("<command>", &line_len);

        return usage;
    }

    fn defaultFormat(comptime flag: meta.Flag) []const u8 {
        return switch (@typeInfo(meta.Unwrap(flag.type))) {
            .bool => "",
            .@"struct" => |s| blk: {
                var fields: []const u8 = "";

                for (s.fields, 0..) |f, i| {
                    fields = fields ++ f.name ++ (if (i < s.fields.len - 1) " " else "");
                }

                break :blk fields;
            },
            else => flag.flag_name[2..],
        };
    }

    fn add(usage: *Usage, item: []const u8, line_len: *usize) void {
        if (line_len.* + " ".len + item.len > max_line_len) {
            const indent_len = "Usage: ".len + usage.command.len;
            usage.body = usage.body ++ "\n" ++ " " ** indent_len;
            line_len.* = indent_len;
        }

        usage.body = usage.body ++ " " ++ item;
        line_len.* += 1 + item.len;
    }
};

const Section = struct {
    header: []const u8,
    items: []const Item = &.{},
    max_name_len: usize = 0,

    const Item = struct {
        name: []const u8,
        desc: ?[]const u8,

        pub fn init(name: []const u8, desc: ?[]const u8) Item {
            return .{
                .name = name,
                .desc = desc,
            };
        }
    };

    pub fn init(header: []const u8) Section {
        return .{
            .header = header,
        };
    }

    pub fn add(section: *Section, item: Item) void {
        section.items = section.items ++ .{item};
        section.max_name_len = @max(section.max_name_len, item.name.len);
    }
};

/// Don't forget to `flush`!
pub fn render(help: Help, term: Terminal, colors: ColorScheme) void {
    help.usage.render(term, colors);

    if (help.description) |description| {
        term.print(colors.command_description, "\n{s}\n", .{description});
    }

    for (help.sections) |section| {
        term.print(colors.header, "\n{s}\n\n", .{section.header});

        for (section.items) |item| {
            term.print(colors.option_name, "  {s}", .{item.name});
            if (item.desc) |desc| {
                term.print(&.{}, " ", .{});

                // Ensure the description gets printed as it looks in the user's Flags struct
                // (Left-align all lines, even with multi-line descriptions)
                var lines = std.mem.tokenizeAny(u8, desc, "\r\n");
                if (lines.next()) |line1| {
                    for (0..(section.max_name_len - item.name.len)) |_| {
                        term.print(&.{}, " ", .{});
                    }
                    term.print(colors.description, "{s}", .{line1});
                }

                while (lines.next()) |line| {
                    term.print(&.{}, "\n", .{});
                    for (0..(section.max_name_len + 3)) |_| {
                        term.print(&.{}, " ", .{});
                    }
                    term.print(colors.description, "{s}", .{line});
                }
            }

            term.print(&.{}, "\n", .{});
        }
    }
}

pub fn generate(Flags: type, info: meta.FlagsInfo, command: []const u8) Help {
    comptime var help: Help = .{
        .usage = Usage.generate(Flags, info, command),
        .description = if (@hasDecl(Flags, "description"))
            @as([]const u8, Flags.description) // description must be a string
        else
            null,
        .sections = &.{},
    };

    const flag_descriptions = meta.getDescriptions(Flags);
    var options: Section = .init("Options:");
    for (info.flags) |flag| {
        options.add(.{
            .name = if (flag.switch_char) |ch|
                std.fmt.comptimePrint("-{c}, {s}", .{ ch, flag.flag_name })
            else
                flag.flag_name,

            .desc = @field(flag_descriptions, flag.field_name),
        });

        // TODO: This can be its own method
        const T = meta.Unwrap(flag.type);
        switch (@typeInfo(T)) {
            inline .@"struct", .@"enum" => |ty| {
                const descriptions = meta.getDescriptions(T);

                for (ty.fields) |field| {
                    options.add(.{
                        .name = "  " ++ meta.toKebab(field.name),
                        .desc = @field(descriptions, field.name),
                    });
                }
            },
            else => {},
        }
    }

    options.add(.init(
        "-h, --help",
        "Show this help and exit",
    ));

    help.sections = help.sections ++ .{options};

    if (info.positionals.len > 0 or meta.hasTrailingField(Flags)) {
        const FlagsPositionals = @FieldType(Flags, meta.special_fields.positional);
        const pos_descriptions = meta.getDescriptions(FlagsPositionals);

        var arguments = Section{ .header = "Arguments:" };
        for (info.positionals) |arg| {
            arguments.add(.{
                .name = arg.arg_name,
                .desc = @field(pos_descriptions, arg.field_name),
            });

            const T = meta.Unwrap(arg.type);
            switch (@typeInfo(T)) {
                inline .@"struct", .@"enum" => |ty| {
                    const descriptions = meta.getDescriptions(T);

                    for (ty.fields) |field| {
                        arguments.add(.{
                            .name = "  " ++ meta.toKebab(field.name),
                            .desc = @field(descriptions, field.name),
                        });
                    }
                },
                else => {},
            }
        }

        if (@hasField(FlagsPositionals, meta.special_fields.trailing)) arguments.add(.init("...", null));

        help.sections = help.sections ++ .{arguments};
    }

    if (info.subcommands.len > 0) {
        var commands: Section = .init("Commands:");

        for (info.subcommands) |cmd| commands.add(.init(
            cmd.command_name,
            if (@hasDecl(cmd.type, "description")) @as([]const u8, @field(cmd.type, "description")) else null,
        ));

        help.sections = help.sections ++ .{commands};
    }

    return help;
}

const Help = @This();

const std = @import("std");
const meta = @import("meta.zig");

const File = std.fs.File;
const ColorScheme = @import("ColorScheme.zig");
const Terminal = @import("Terminal.zig");
