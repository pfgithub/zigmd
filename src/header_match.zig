const std = @import("std");

pub fn implements(
    comptime Implementation: type,
    comptime Header: type,
    comptime context: []const u8,
) void {
    comptime {
        if (Header == Implementation) return;

        const header = @typeInfo(Header);
        const implementation = @typeInfo(Implementation);

        if (std.meta.activeTag(header) != std.meta.activeTag(implementation))
            @compileError(context ++ ": Implementation has incorrect type (expected" ++ @tagName(std.meta.activeTag(header)) ++ ", got " ++ @tagName(std.meta.activeTag(implementation)) ++ ")");

        switch (header) {
            .Struct => structImplements(header.Struct, implementation.Struct, context ++ " = struct"),
            else => @compileError(context ++ "Not supported yet: " ++ @tagName(std.meta.activeTag(header))),
        }
    }
}

pub fn structImplements(
    comptime implementation: std.builtin.TypeInfo.Struct,
    comptime header: std.builtin.TypeInfo.Struct,
    comptime context: []const u8,
) void {
    comptime {
        for (header.decls) |decl| {
            if (!decl.is_pub) continue;

            // ensure implementation has decl
            if (!@hasDecl(Implementation, decl.name))
                @compileError(context ++ ": Implementation is missing declaration `" + decl.name + "`");

            switch (header.Data) {
                .Type => implements(
                    @field(Implementation, decl.name),
                    header.Data.Type,
                    context ++ " > decl " ++ decl.name,
                ),
                else => @compileError(context ++ "Not supported yet: " ++ @tagName(std.meta.activeTag(header.Data))),
            }
        }
        for (header.fields) |field| {
            // ensure implementation has field
        }
    }
}

test "" {
    implements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u32;
    }, "Test > ");
}
