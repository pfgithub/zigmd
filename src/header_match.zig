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
        else => @compileError(context ++ " >: Not supported yet: " ++ @tagName(headerTag)),
    }
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

        // ensure implementation has decl
        if (!@hasDecl(Implementation, decl.name))
            @compileError(context ++ " >: Implementation is missing declaration `pub " ++ decl.name ++ "`");

        switch (decl.data) {
            .Type => |typ| implements(
                @field(Implementation, decl.name),
                typ,
                context ++ " > decl " ++ decl.name,
            ),
            else => |v| @compileError(context ++ " >: Not supported yet: " ++ @tagName(@TagType(@as(@TypeOf(v), v)))),
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
