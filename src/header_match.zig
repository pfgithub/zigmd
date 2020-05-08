const std = @import("std");

pub fn implements(
    comptime Implementation: type,
    comptime Header: type,
    comptime context: []const u8,
) void {
    const header = @typeInfo(Header);
    const implementation = @typeInfo(Implementation);

    const headerTag = @as(@TagType(@TypeOf(header)), header);
    const implementationTag = @as(@TagType(@TypeOf(implementation)), implementation);
    if (headerTag != implementationTag)
        @compileError(context ++ " >: Implementation has incorrect type (expected " ++ @tagName(headerTag) ++ ", got " ++ @tagName(implementationTag) ++ ")");

    const namedContext = context ++ ": " ++ @tagName(headerTag);
    switch (header) {
        .Struct => structImplements(Implementation, Header, namedContext),
        else => @compileError(context ++ " >: Not supported yet: " ++ @tagName(headerTag)),
    }
}

pub fn structImplements(
    comptime Implementation: type,
    comptime Header: type,
    comptime context: []const u8,
) void {
    const header = @typeInfo(Header).Struct;
    const implementation = @typeInfo(Implementation).Struct;

    for (header.decls) |decl| {
        if (!decl.is_pub) continue;

        // ensure implementation has decl
        if (!@hasDecl(Implementation, decl.name))
            @compileError(context ++ " >: Implementation is missing declaration `" + decl.name + "`");

        switch (decl.data) {
            .Type => |typ| implements(
                @field(Implementation, decl.name),
                typ,
                context ++ " > decl " ++ decl.name,
            ),
            else => |v| @compileError(context ++ " >: Not supported yet: " ++ @tagName(@TagType(@as(@TypeOf(v), v)))),
        }
    }
    for (header.fields) |field| {
        // ensure implementation has field
    }
}

test "" {
    comptime implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u32;
    }, "base");
}
