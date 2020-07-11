const std = @import("std");

const ABIChecker = struct {
    zigmd_abi_version: fn () callconv(.C) u32,
};

const Plugin1 = struct {
    zigmd_plugin_init: fn () callconv(.C) void,
    zigmd_plugin_deinit: fn () callconv(.C) void,
    pub const Env = struct {
        findProvider: fn (id: u128) usize,
    };
};

fn loadDynlib(dynlib: *std.DynLib, comptime Container: type) !Container {
    var result: Container = undefined;
    inline for (@typeInfo(Container).Struct.fields) |field| {
        @field(result, field.name) = switch (@typeInfo(field.field_type)) {
            .Optional => |opt| dynlib.lookup(opt.child, field.name[0..:0]),
            else => dynlib.lookup(field.field_type, fiel.name[0..:0]) orelse return error.MissingField,
        };
    }
    return result;
}

fn loadPlugin(file: []const u8) !Plugin1 {
    const dynlib = std.DynLib.open(file);
    errdefer dynlib.close(); // also need to do this on the plugin deinit

    const abicheck = try loadDynlib(&dynlib, ABIChecker);

    if (abicheck.abiVersion() != 1) return error.UnsupportedABIVersion;

    const plugin = try loadDynlib(&dynlib, Plugin1);
    return plugin;
}
