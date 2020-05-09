const std = @import("std");

fn seen(comptime a: type, comptime list: *[]const type) bool {
    for (list.*) |itm| {
        if (a == itm) return true;
    }
    list.* = list.* ++ [_]type{a};
    return false;
}

test "seen" {
    comptime {
        var array: [0]type = [_]type{};
        var slice: []const type = &array;
        if (seen(u8, &slice)) unreachable;
        if (seen(u16, &slice)) unreachable;
        if (!seen(u8, &slice)) unreachable;
    }
}

// the std.testing one doesn't work at comptime
pub fn expectEqual(comptime b: ?[]const u8, comptime a: ?[]const u8) void {
    if (a == null) {
        if (b == null)
            return;
        @compileError("Expected null, got `" ++ b.? ++ "`");
    } else if (b == null)
        @compileError("Expected `" ++ a.? ++ "`, got null");
    if (!std.mem.eql(u8, a.?, b.?))
        @compileError("Expected `" ++ a.? ++ "`, got `" ++ b.? ++ "`");
}

pub fn implements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
) ?[]const u8 {
    if (Header == Implementation) return null;

    const header = @typeInfo(Header);
    const implementation = @typeInfo(Implementation);

    const headerTag = @as(@TagType(@TypeOf(header)), header);
    const implementationTag = @as(@TagType(@TypeOf(implementation)), implementation);
    if (headerTag != implementationTag)
        return (context ++ " >: Implementation has incorrect type (expected " ++ @tagName(headerTag) ++ ", got " ++ @tagName(implementationTag) ++ ")");

    const namedContext: []const u8 = context ++ ": " ++ @tagName(headerTag);
    switch (header) {
        .Struct => if (structImplements(Header, Implementation, namedContext)) |err|
            return err,
        .Int, .Float, .Bool => {
            if (Header != Implementation) {
                return (namedContext ++ " >: Types differ. Expected: " ++ @typeName(Header) ++ ", Got: " ++ @typeName(Implementation) ++ ".");
            }
        },
        .Fn => if (fnImplements(Header, Implementation, namedContext)) |err|
            return err,
        else => return (context ++ " >: Not supported yet: " ++ @tagName(headerTag)),
    }
    return null;
}

pub fn fnImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
) ?[]const u8 {
    const header = @typeInfo(Header).Fn;
    const impl = @typeInfo(Implementation).Fn;

    if (header.is_generic) return (context ++ " >: Generic functions are not supported yet.");
    if (header.is_var_args) return (context ++ " >: VarArgs functions are not supported yet.");
    if (impl.is_generic) return (context ++ " >: Expected non-generic, got generic");
    if (impl.is_var_args) return (context ++ " >: Expected non-varargs, got varargs.");
    if (header.calling_convention != impl.calling_convention) return (context ++ " >: Wrong calling convention.");

    if (implements(header.return_type.?, impl.return_type.?, context ++ " > return")) |err|
        return err;

    if (header.args.len != impl.args.len) return (context ++ " >: Expected {} arguments, got {}.");
    for (header.args) |headerarg, i| {
        const implarg = impl.args[i];

        var buf = [_]u8{0} ** 100;
        const res = std.fmt.bufPrint(&buf, " > args[{}]", .{i}) catch @compileError("buffer out of space");
        const argContext = context ++ res;

        if (headerarg.is_generic) return (argContext ++ " >: Generic args are not supported yet.");
        if (implarg.is_generic) return (argContext ++ " >: Expected non-generic, got generic.");
        if (headerarg.is_noalias != implarg.is_noalias) return (argContext ++ " >: Expected noalias?, got noalias?");
        if (implements(headerarg.arg_type.?, implarg.arg_type.?, argContext)) |v| return v;
    }

    return null;
}

pub fn structImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
) ?[]const u8 {
    const header = @typeInfo(Header).Struct;
    const implementation = @typeInfo(Implementation).Struct;

    for (header.decls) |decl| {
        if (!decl.is_pub) continue;

        const namedContext = context ++ " > decl " ++ decl.name;

        // ensure implementation has decl
        if (!@hasDecl(Implementation, decl.name))
            return (namedContext ++ " >: Implementation is missing declaration.");

        // using for as a find with break and else doesn't seem to be working at comptime, so this works as an alternative
        const impldecl = blk: {
            for (implementation.decls) |idecl, i| {
                if (std.mem.eql(u8, decl.name, idecl.name))
                    break :blk idecl;
            }
            return (namedContext ++ " >: Implementation is missing declaration.");
        };

        if (!impldecl.is_pub) return (namedContext ++ " >: Implementation declaration is private.");

        const headerDataType = @as(@TagType(@TypeOf(decl.data)), decl.data);
        const implDataType = @as(@TagType(@TypeOf(impldecl.data)), impldecl.data);

        if (headerDataType != implDataType)
            return (namedContext ++ " >: DataTypes differ. Expected: " ++ @tagName(headerDataType) ++ ", got " ++ @tagName(implDataType));

        switch (decl.data) {
            .Type => |typ| if (implements(
                typ,
                @field(Implementation, decl.name),
                namedContext,
            )) |err| return err,
            .Fn => |fndecl| {
                const fnimpl = impldecl.data.Fn;
                if (implements(fndecl.fn_type, fnimpl.fn_type, namedContext)) |err|
                    return err;
            },
            else => |v| return (namedContext ++ " >: Not supported yet: " ++ @tagName(headerDataType)),
        }
    }
    for (implementation.decls) |decl| {
        if (!@hasDecl(Header, decl.name))
            return (context ++ " >: Header has extra disallowed declaration `pub " ++ decl.name ++ "`");
    }

    for (header.fields) |field| {
        // ensure implementation has field
        if (!@hasField(Implementation, field.name))
            return (context ++ " >: Implementation is missing field `" ++ field.name ++ "`");
        for (implementation.fields) |implfld| {
            if (!std.mem.eql(u8, field.name, implfld.name)) continue;

            if (implements(field.field_type, implfld.field_type, context ++ " > " ++ field.name)) |err| return err;
        }
    }
    return null;
}

test "extra declaration" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        pub const B = u32;
    }, "base"), "base: Struct >: Header has extra disallowed declaration `pub B`");
}

test "extra private declaration ok" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        const B = u32;
    }, "base"), "base: Struct >: Header has extra disallowed declaration `pub B`");
}

test "missing declaration" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
    }, struct {
        pub const B = u32;
    }, "base"), "base: Struct > decl A >: Implementation is missing declaration.");
}

test "integer different" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u32;
    }, "base"), "base: Struct > decl A: Int >: Types differ. Expected: u64, Got: u32.");
}

test "integer equivalent" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
    }, "base"), null);
}

test "fields missing" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
        a: A,
        b: u32,
        c: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }, "base"), "base: Struct >: Implementation is missing field `c`");
}

test "fields wrong type" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
        a: A,
        b: u64,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }, "base"), "base: Struct > b: Int >: Types differ. Expected: u64, Got: u32.");
}

test "fields equivalent + extra private" {
    comptime expectEqual(implements(struct {
        pub const A = u64;
        a: A,
        b: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }, "base"), null);
}

test "fn different return values" {
    comptime expectEqual(implements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct) struct { a: u64 } {
            return undefined;
        }
    }, "base"), "base: Struct > decl a: Fn > return: Struct >: Implementation is missing field `typ`");
}

test "fn equivalent" {
    comptime expectEqual(implements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct, arg2: u64, arg3: bool) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct, arg2: u64, arg3: bool) Struct {
            return undefined;
        }
    }, "base"), null);
}

test "fields" {
    comptime expectEqual(implements(struct {
        q: u64,
    }, struct {
        q: u32,
    }, "base"), "base: Struct > q: Int >: Types differ. Expected: u64, Got: u32.");
}

test "fn different args" {
    comptime expectEqual(implements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg2: u64, arg: Struct, arg3: bool) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg2: u64, arg: struct { typ: u32 }, arg3: bool) Struct {
            return undefined;
        }
    }, "base"), "base: Struct > decl a: Fn > args[1]: Struct > typ: Int >: Types differ. Expected: u64, Got: u32.");
}

// uh oh! recursion will require special workarounds!
// test "pass" {
//     comptime implements(struct {
//         pub const Recursion = struct {
//             pub const This = Recursion;
//         };
//     }, struct {
//         pub const Recursion = struct {
//             pub const This = Recursion;
//         };
//     }, "base");
// }
