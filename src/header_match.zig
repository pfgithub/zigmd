const std = @import("std");

pub fn implements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
) void {
    const header = @typeInfo(Header);
    const implementation = @typeInfo(Implementation);

    const headerTag = @as(@TagType(@TypeOf(header)), header);
    const implementationTag = @as(@TagType(@TypeOf(implementation)), implementation);
    if (headerTag != implementationTag)
        @compileError(context ++ " >: Implementation has incorrect type (expected " ++ @tagName(headerTag) ++ ", got " ++ @tagName(implementationTag) ++ ")");

    const namedContext: []const u8 = context ++ ": " ++ @tagName(headerTag);
    switch (header) {
        .Struct => structImplements(Header, Implementation, namedContext),
        .Int, .Float => {
            if (Header != Implementation) {
                @compileError(namedContext ++ " >: Types differ. Expected: " ++ @typeName(Header) ++ ", Got: " ++ @typeName(Implementation) ++ ".");
            }
        },
        .Fn => fnImplements(Header, Implementation, namedContext),
        else => @compileError(context ++ " >: Not supported yet: " ++ @tagName(headerTag)),
    }
}

pub fn fnImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
) void {
    const header = @typeInfo(Header).Fn;
    const impl = @typeInfo(Implementation).Fn;

    implements(header.return_type.?, impl.return_type.?, context ++ " > return");
}

pub fn structImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
) void {
    const header = @typeInfo(Header).Struct;
    const implementation = @typeInfo(Implementation).Struct;

    for (header.decls) |decl| {
        if (!decl.is_pub) continue;

        const namedContext = context ++ " > decl " ++ decl.name;

        // ensure implementation has decl
        if (!@hasDecl(Implementation, decl.name))
            @compileError(namedContext ++ " >: Implementation is missing declaration.");

        // using for as a find with break and else doesn't seem to be working at comptime, so this works as an alternative
        const impldecl = blk: {
            for (implementation.decls) |idecl, i| {
                if (std.mem.eql(u8, decl.name, idecl.name))
                    break :blk idecl;
            }
            @compileError(namedContext ++ " >: Implementation is missing declaration.");
        };

        if (!impldecl.is_pub) @compileError(namedContext ++ " >: Implementation declaration is private.");

        const headerDataType = @as(@TagType(@TypeOf(decl.data)), decl.data);
        const implDataType = @as(@TagType(@TypeOf(impldecl.data)), impldecl.data);

        if (headerDataType != implDataType)
            @compileError(namedContext ++ " >: DataTypes differ. Expected: " ++ @tagName(headerDataType) ++ ", got " ++ @tagName(implDataType));

        switch (decl.data) {
            .Type => |typ| implements(
                typ,
                @field(Implementation, decl.name),
                namedContext,
            ),
            .Fn => |fndecl| {
                const fnimpl = impldecl.data.Fn;
                implements(fndecl.fn_type, fnimpl.fn_type, namedContext);
            },
            else => |v| @compileError(namedContext ++ " >: Not supported yet: " ++ @tagName(headerDataType)),
        }
    }
    for (implementation.decls) |decl| {
        if (!@hasDecl(Header, decl.name))
            @compileError(context ++ " >: Header has extra disallowed declaration `pub " ++ decl.name ++ "`");
    }
    for (header.fields) |field| {
        // ensure implementation has field
        if (!@hasField(Implementation, field.name))
            @compileError(context ++ " >: Implementation is missing field `" ++ field.name ++ "`");
        for (implementation.fields) |implfld| {
            if (!std.meta.eql(field.name, implfld.name)) continue;

            implements(field.field_type, implfld.field_type, context ++ " > " ++ field.name);
        }
    }
}

test "fail" {
    comptime implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        pub const B = u32;
    }, "base");
}

test "fail" {
    comptime implements(struct {
        pub const A = u64;
    }, struct {
        pub const B = u32;
    }, "base");
}

test "fail" {
    comptime implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u32;
    }, "base");
}

test "pass" {
    comptime implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
    }, "base");
}

test "fail" {
    comptime implements(struct {
        pub const A = u64;
        a: A,
        b: u32,
        c: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }, "base");
}

test "fail" {
    comptime implements(struct {
        pub const A = u64;
        a: A,
        b: u64,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }, "base");
}

test "pass" {
    comptime implements(struct {
        pub const A = u64;
        a: A,
        b: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }, "base");
}

test "fail" {
    comptime implements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct) struct { a: u64 } {
            return undefined;
        }
    }, "base");
}

test "pass" {
    comptime implements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct) Struct {
            return undefined;
        }
    }, "base");
}

// TODO test recursive struct (pub const Struct = struct {pub const S = Struct}}])
