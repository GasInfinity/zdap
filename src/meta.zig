const std = @import("std");

pub const special_fields = struct {
    pub const subcommand = "-";
    pub const positional = "--";
    pub const trailing = "...";
};

pub const FlagsInfo = struct {
    flags: []const Flag = &.{},
    positionals: []const Positional = &.{},
    subcommands: []const SubCommand = &.{},
    optional_subcommands: bool = false,
};

const SubCommand = struct {
    /// A nested Flags struct.
    type: type,
    field_name: []const u8,
    command_name: []const u8,
};

pub const Flag = struct {
    type: type,
    default_value: ?*const anyopaque,
    field_name: []const u8,
    /// For field_name == "my_flag" -> flag_name == "--my-flag".
    flag_name: []const u8,
    switch_char: ?u8,

    pub fn isOptional(flag: Flag) bool {
        return flag.type == bool or
            @typeInfo(flag.type) == .optional or
            flag.default_value != null;
    }
};

pub const Positional = struct {
    type: type,
    default_value: ?*const anyopaque,
    field_name: []const u8,
    /// The placeholder name, e.g `<FILE>`
    arg_name: []const u8,

    pub fn isOptional(positional: Positional) bool {
        return @typeInfo(positional.type) == .optional or
            positional.default_value != null;
    }
};

pub fn info(comptime Flags: type) FlagsInfo {
    std.debug.assert(@inComptime());
    if (@typeInfo(Flags) != .@"struct") {
        compileError("input type is not a struct: {s}", .{@typeName(Flags)});
    }

    var command = FlagsInfo{};

    const switches = getSwitches(Flags);

    for (@typeInfo(Flags).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, special_fields.positional)) switch (@typeInfo(field.type)) {
            .@"struct" => |s| {
                var seen_optional = false;

                for (s.fields) |positional| {
                    if (std.mem.eql(u8, positional.name, special_fields.trailing)) {
                        continue;
                    }

                    if (@typeInfo(positional.type) != .optional) {
                        if(seen_optional) compileError("non-optional positional field after optional: {s}", .{positional.name});
                    } else seen_optional = true;

                    command.positionals = command.positionals ++ .{Positional{
                        .type = positional.type,
                        .default_value = positional.default_value_ptr,
                        .field_name = positional.name,
                        .arg_name = positionalName(positional),
                    }};
                }

                continue;
            },
            else => compileError("'--' (positional) field is not a struct type: {s}", .{@typeName(field.type)})
        };
            

        if (std.mem.eql(u8, field.name, special_fields.subcommand)) {
            const union_info = switch (@typeInfo(field.type)) {
                .optional => |o| if(@typeInfo(o.child) == .@"union" and @typeInfo(o.child).@"union".tag_type != null) blk: {
                    command.optional_subcommands = true;
                    break :blk @typeInfo(o.child).@"union";
                } else
                    compileError("'-' (subcommand) field is not a tagged union {s}", .{@typeName(field.type)}),
                .@"union" => |u| if(u.tag_type != null)
                    u
                else 
                    compileError("'-' (subcommand) field is not a tagged union {s}", .{@typeName(field.type)}),
                else => compileError("'-' (subcommand) is not a tagged union: {s}", .{@typeName(field.type)}),
            };

            for (union_info.fields) |cmd| {
                command.subcommands = command.subcommands ++ .{SubCommand{
                    .type = cmd.type,
                    .field_name = cmd.name,
                    .command_name = toKebab(cmd.name),
                }};
            }

            continue;
        }
        
        switch (@typeInfo(UnwrapOptional(field.type))) {
            .int, .float, .bool, .@"enum", .pointer => {
                command.flags = command.flags ++ .{Flag{
                    .type = field.type,
                    .default_value = field.default_value_ptr,
                    .field_name = field.name,
                    .flag_name = "--" ++ toKebab(field.name),
                    .switch_char = @field(switches, field.name),
                }};
            },
            else => compileError("can't parse '{s}': {s}", .{field.name, @typeName(field.type)}), 
        }
    }

    if(command.subcommands.len > 0 and command.positionals.len > 0) compileError("cannot have subcommands and positionals at the same time", .{});

    if(command.subcommands.len > 0) {
        if(!command.optional_subcommands and command.flags.len > 0) compileError("cannot have flags alongside non-optional subcommands", .{});

        for (command.flags) |flag| {
            if(!flag.isOptional()) compileError("cannot have non-optional flags with subcommands", .{});
        }
    }
    return command;
}

pub fn hasPositionals(comptime Flags: type) bool {
    return @hasField(Flags, special_fields.positional);
}

pub fn hasTrailingField(comptime Flags: type) bool {
    return hasPositionals(Flags) and
        @hasField(@FieldType(Flags, special_fields.positional), special_fields.trailing);
}

// A struct with fields identical to T except every field type is ?F and the default value is null.
fn FieldAttr(T: type, F: type) type {
    return std.enums.EnumFieldStruct(std.meta.FieldEnum(T), ?F, @as(?F, null));
}

fn getSwitches(T: type) FieldAttr(T, u8) {
    var switches: FieldAttr(T, u8) = .{};

    if (!@hasDecl(T, "switches")) {
        return switches;
    }

    const Switches = @TypeOf(T.switches);
    if (@typeInfo(Switches) != .@"struct") {
        compileError("switches is not a struct value: {s}", .{@typeName(Switches)});
    }

    const switch_fields = @typeInfo(Switches).@"struct".fields;
    for (switch_fields, 0..) |switch_field, field_index| {
        if (!@hasField(T, switch_field.name)) {
            compileError("switch name does not match any field: {s}", .{switch_field.name});
        }

        const switch_val = @field(T.switches, switch_field.name);

        if (@TypeOf(switch_val) != comptime_int) {
            compileError("switch value is not a character: {any}", .{switch_val});
        }

        const switch_char = std.math.cast(u8, switch_val) orelse compileError("switch value is not a character: {any}", .{switch_val});

        if (!std.ascii.isAlphanumeric(switch_char)) {
            compileError("switch character is not a letter or digit: {c}", .{switch_char});
        }

        for (switch_fields[field_index + 1 ..]) |other_field| {
            const other_val = @field(T.switches, other_field.name);
            if (switch_val == other_val) compileError("duplicate switch values: {s} and {s}", .{ switch_field.name, other_field.name });
        }

        @field(switches, switch_field.name) = switch_char;
    }

    return switches;
}

pub fn getDescriptions(T: type) FieldAttr(T, []const u8) {
    var descriptions: FieldAttr(T, []const u8) = .{};

    if (!@hasDecl(T, "descriptions")) {
        return descriptions;
    }

    const D = @TypeOf(T.descriptions);
    if (@typeInfo(D) != .@"struct") {
        compileError("descriptions is not a struct value: {s}", .{@typeName(D)});
    }

    for (@typeInfo(D).@"struct".fields) |field| {
        if (!@hasField(T, field.name)) {
            compileError("description name does not match any field: '{s}'", .{field.name});
        }

        const description = @field(T.descriptions, field.name);
        @field(descriptions, field.name) =
            @as([]const u8, description); // description must be a string
    }

    return descriptions;
}

pub fn getFormats(T: type) FieldAttr(T, []const u8) {
    var formats: FieldAttr(T, []const u8) = .{};
    if (!@hasDecl(T, "formats")) {
        return formats;
    }

    const F = @TypeOf(T.formats);
    if (@typeInfo(F) != .@"struct") {
        compileError("formats is not a struct value: {s}", .{@typeName(F)});
    }

    for (@typeInfo(F).@"struct".fields) |field| {
        if (!@hasField(T, field.name)) {
            compileError("format name does not match any field: {s}", .{field.name});
        }

        const format = @field(T.formats, field.name);
        @field(formats, field.name) =
            @as([]const u8, format); // format must be a string
    }

    return formats;
}

pub fn compileError(comptime fmt: []const u8, args: anytype) void {
    @compileError("(flags) " ++ std.fmt.comptimePrint(fmt, args));
}

pub fn UnwrapOptional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |opt| opt.child,
        else => T,
    };
}

/// Casts the opaque default_value, if it exists, to a Flag/Positional's actual type.
pub fn defaultValue(comptime option: anytype) ?option.type {
    const default_opaque = option.default_value orelse return null;
    const default: *const option.type = @ptrCast(@alignCast(default_opaque));
    return default.*;
}

/// Converts "positional_field" to "<POSITIONAL_FIELD>.".
pub fn positionalName(comptime field: std.builtin.Type.StructField) []const u8 {
    comptime var upper: []const u8 = &.{};
    comptime for (field.name) |c| {
        upper = upper ++ .{std.ascii.toUpper(c)};
    };
    return std.fmt.comptimePrint("<{s}>", .{upper});
}

/// Converts from snake_case to kebab-case at comptime.
pub fn toKebab(comptime string: []const u8) []const u8 {
    comptime var name: []const u8 = "";

    inline for (string) |ch| name = name ++ .{switch (ch) {
        '_' => '-',
        else => ch,
    }};

    return name;
}
