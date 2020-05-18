const std = @import("std");

const Memo = struct {
    list: []const type = &[_]type{},
    pub fn seen(comptime memo: *Memo, comptime Type: type) bool {
        for (memo.list) |KnownType| {
            if (Type == KnownType) return true;
        }
        memo.list = memo.list ++ [_]type{Type};
        return false;
    }
};

test "seen" {
    comptime {
        var memo: Memo = .{};
        if (memo.seen(u8)) unreachable;
        if (memo.seen(u16)) unreachable;
        if (!memo.seen(u8)) unreachable;
        const StructA = struct {};
        const StructB = struct {};
        if (memo.seen(StructA)) unreachable;
        if (memo.seen(StructB)) unreachable;
        if (!memo.seen(StructA)) unreachable;
        if (!memo.seen(StructB)) unreachable;
    }
}

pub fn conformsTo(comptime Header: type, comptime Implementation: type) void {
    if (testingImplements(Header, Implementation)) |err| @compileError("Does not conform.\n " ++ err);
}
fn testingImplements(comptime Header: type, comptime Implementation: type) ?[]const u8 {
    var memo: Memo = .{};
    return implements(Header, Implementation, "base", &memo);
}

fn expectEqual(comptime b: ?[]const u8, comptime a: ?[]const u8) void {
    if (b == null) {
        if (a == null)
            return;
        @compileError("Expected null, got `" ++ b.? ++ "`");
    } else if (a == null)
        @compileError("Expected `" ++ b.? ++ "`, got null");
    if (!std.mem.eql(u8, a.?, b.?))
        @compileError("Expected `" ++ a.? ++ "`, got `" ++ b.? ++ "`");
}

fn memoHeaderImpl(
    comptime Header: type,
    comptime Implementation: type,
) type {
    return struct { header: Header, implementation: Implementation };
}

fn implements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
    comptime memo: *Memo,
) ?[]const u8 {
    if (Header == Implementation) return null;
    if (memo.seen(memoHeaderImpl(Header, Implementation)))
        return null;

    const header = @typeInfo(Header);
    const implementation = @typeInfo(Implementation);

    if ((header == .Struct or header == .Union or header == .Enum) and @hasDecl(Header, "__custom_type_compare")) {
        const namedContext = context ++ "[custom]";
        const compare = struct {
            fn a(comptime H: type, comptime I: type) ?[]const u8 {
                return implements(H, I, "", memo);
            }
        }.a;
        if (Header.__custom_type_compare(Implementation, compare)) |err|
            return context ++
                "[custom]" ++
                if (err[0] == ' ' or err[0] == ':') " > custom" ++ err else " >: " ++ err;
        return null;
    }

    const headerTag = @as(@TagType(@TypeOf(header)), header);
    const implementationTag = @as(@TagType(@TypeOf(implementation)), implementation);
    if (headerTag != implementationTag)
        return (context ++ " >: Implementation has incorrect type (expected " ++ @tagName(headerTag) ++ ", got " ++ @tagName(implementationTag) ++ ")");

    const namedContext: []const u8 = context ++ ": " ++ @tagName(headerTag) ++ "\n  ";

    switch (header) {
        .Struct => if (structImplements(Header, Implementation, namedContext, memo)) |err|
            return err,
        .Int, .Float, .Bool => {
            if (Header != Implementation) {
                return (namedContext ++ " >: Types differ. Expected: " ++ @typeName(Header) ++ ", Got: " ++ @typeName(Implementation) ++ ".");
            }
        },
        .Fn => if (fnImplements(Header, Implementation, namedContext, memo)) |err|
            return err,
        .Pointer => if (pointerImplements(Header, Implementation, namedContext, memo)) |err|
            return err,
        .ErrorUnion => if (errorUnionImplements(Header, Implementation, namedContext, memo)) |err|
            return err,
        .ErrorSet => if (errorSetImplements(Header, Implementation, namedContext, memo)) |err|
            return err,
        else => return (namedContext ++ " >: Not supported yet: " ++ @tagName(headerTag)),
    }
    return null;
}

fn errorSetImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
    comptime memo: *Memo,
) ?[]const u8 {
    const header = @typeInfo(Header).ErrorSet orelse
        return context ++ " > ? TODO investigate";
    const impl = @typeInfo(Implementation).ErrorSet orelse
        return context ++ " > impl? TODO investigate";

    if (header.len == 0 and impl.len == 0)
        return context ++ " > Empty error sets are not supported due to potential compiler bugs. Make sure the implementation has at least one error.";
    // this is bad for explicit catches
    // if (header.len != impl.len)
    //     return context ++ " > Error sets differ";
    // for (header) |errv| {
    //     for (impl) |errc| blk: {
    //         if (errv.value == errc.value) break :blk;
    //     } else return context ++ " > Implementation missing error " ++ errv.name;
    // }
    if (Header != Implementation) {
        for (header) |errv| {
            for (impl) |errc| {
                if (errv.value == errc.value) break;
            } else return context ++ "> Implementation missing error `" ++ errv.name ++ "`";
        }
        for (impl) |errv| {
            for (header) |errc| {
                if (errv.value == errc.value) break;
            } else return context ++ "> Implementation has extra error `" ++ errv.name ++ "`";
        }
        // ok, error sets are the same.
    }

    return null;
}
fn errorUnionImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
    comptime memo: *Memo,
) ?[]const u8 {
    // these cannot be passed as args because of a compiler bug
    const header = @typeInfo(Header).ErrorUnion;
    const impl = @typeInfo(Implementation).ErrorUnion;

    if (implements(header.error_set, impl.error_set, context ++ " > ErrorSet!", memo)) |err|
        return err;
    if (implements(header.error_set, impl.error_set, context ++ " > !Payload", memo)) |err|
        return err;

    return null;
}

fn pointerImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
    comptime memo: *Memo,
) ?[]const u8 {
    // these cannot be passed as args because of a compiler bug
    const header = @typeInfo(Header).Pointer;
    const impl = @typeInfo(Implementation).Pointer;

    if (header.is_volatile) return (context ++ " >: Pointer volatility is not supported yet.");
    if (impl.is_volatile) return (context ++ " >: Expected not volatile.");
    // ignoring sentinel for now, it looks complicated
    if (header.is_const != impl.is_const) return (context ++ " >: Expected constness {}, got {}.");
    // if (header.alignment != impl.alignment) return (context ++ " >: Expected align({}), got align({})."); // does not appear to be useful
    if (header.is_allowzero != impl.is_allowzero) return (context ++ " >: Expected allowzero {}, got {}.");

    if (implements(header.child, impl.child, context ++ " > .*", memo)) |err|
        return err;

    return null;
}

fn fnImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
    comptime memo: *Memo,
) ?[]const u8 {
    const header = @typeInfo(Header).Fn;
    const impl = @typeInfo(Implementation).Fn;

    if (header.is_generic) return (context ++ " >: Generic functions are not supported yet.");
    if (header.is_var_args) return (context ++ " >: VarArgs functions are not supported yet.");
    if (impl.is_generic) return (context ++ " >: Expected non-generic, got generic");
    if (impl.is_var_args) return (context ++ " >: Expected non-varargs, got varargs.");
    if (header.calling_convention != impl.calling_convention) return (context ++ " >: Wrong calling convention.");

    if (implements(header.return_type.?, impl.return_type.?, context ++ " > return", memo)) |err|
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
        if (implements(headerarg.arg_type.?, implarg.arg_type.?, argContext, memo)) |v| return v;
    }

    return null;
}

fn structImplements(
    comptime Header: type,
    comptime Implementation: type,
    comptime context: []const u8,
    comptime memo: *Memo,
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
                memo,
            )) |err| return err,
            .Fn => |fndecl| {
                const fnimpl = impldecl.data.Fn;
                if (implements(fndecl.fn_type, fnimpl.fn_type, namedContext, memo)) |err|
                    return err;
            },
            else => |v| return (namedContext ++ " >: Not supported yet: " ++ @tagName(headerDataType)),
        }
    }
    for (implementation.decls) |decl| {
        if (!@hasDecl(Header, decl.name) and decl.is_pub)
            return (context ++ " >: Header has extra disallowed declaration `pub " ++ decl.name ++ "`");
    }

    for (header.fields) |field| {
        // ensure implementation has field
        if (!@hasField(Implementation, field.name))
            return (context ++ " >: Implementation is missing field `" ++ field.name ++ "`");
        for (implementation.fields) |implfld| {
            if (!std.mem.eql(u8, field.name, implfld.name)) continue;

            if (implements(field.field_type, implfld.field_type, context ++ " > " ++ field.name, memo)) |err| return err;
        }
    }
    return null;
}

pub fn CustomTypeCompare(comptime comparisonFn: fn (type, var) ?[]const u8) type {
    return struct {
        const __custom_type_compare = comparisonFn;
    };
}

test "extra declaration" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        pub const B = u32;
    }), "base: Struct >: Header has extra disallowed declaration `pub B`");
}

test "extra private declaration ok" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        const B = u32;
    }), "base: Struct >: Header has extra disallowed declaration `pub B`");
}

test "missing declaration" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const B = u32;
    }), "base: Struct > decl A >: Implementation is missing declaration.");
}

test "integer different" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u32;
    }), "base: Struct > decl A: Int >: Types differ. Expected: u64, Got: u32.");
}

test "integer equivalent" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
    }), null);
}

test "fields missing" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
        a: A,
        b: u32,
        c: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }), "base: Struct >: Implementation is missing field `c`");
}

test "fields wrong type" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
        a: A,
        b: u64,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }), "base: Struct > b: Int >: Types differ. Expected: u64, Got: u32.");
}

test "fields equivalent + extra private" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
        a: A,
        b: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    }), null);
}

test "fn different return values" {
    comptime expectEqual(testingImplements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct) struct { a: u64 } {
            return undefined;
        }
    }), "base: Struct > decl a: Fn > return: Struct >: Implementation is missing field `typ`");
}

test "fn equivalent" {
    comptime expectEqual(testingImplements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct, arg2: u64, arg3: bool) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct, arg2: u64, arg3: bool) Struct {
            return undefined;
        }
    }), null);
}

test "fields" {
    comptime expectEqual(testingImplements(struct {
        q: u64,
    }, struct {
        q: u32,
    }), "base: Struct > q: Int >: Types differ. Expected: u64, Got: u32.");
}

test "fn different args" {
    comptime expectEqual(testingImplements(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg2: u64, arg: Struct, arg3: bool) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg2: u64, arg: struct { typ: u32 }, arg3: bool) Struct {
            return undefined;
        }
    }), "base: Struct > decl a: Fn > args[1]: Struct > typ: Int >: Types differ. Expected: u64, Got: u32.");
}

test "basic recursion" {
    comptime expectEqual(comptime testingImplements(struct {
        pub const Recursion = struct {
            pub const This = Recursion;
        };
    }, struct {
        pub const Recursion = struct {
            pub const This = Recursion;
        };
    }), null);
}
test "fn this arg recursion" {
    comptime expectEqual(testingImplements(struct {
        pub const Ritigo = struct {
            pub fn measureWidth(ritigo: Ritigo) u64 {
                return undefined;
            }
        };
    }, struct {
        pub const Ritigo = struct {
            pub fn measureWidth(ritigo: Ritigo) u64 {
                return undefined;
            }
        };
    }), null);
}
test "" {
    comptime expectEqual(testingImplements(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: var) ?[]const u8 {
                return if (Other == u64) null else "Expected u64";
            }
        }.a),
    }, struct {
        a: u32,
    }), "base: Struct > a[custom] >: Expected u64");
}
test "" {
    comptime expectEqual(testingImplements(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: var) ?[]const u8 {
                return if (Other == u64) null else "Expected u64";
            }
        }.a),
    }, struct {
        a: u64,
    }), null);
}
test "" {
    comptime expectEqual(testingImplements(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: var) ?[]const u8 {
                if (compare(struct { one: u64 }, Other)) |err| return err;
                return null;
            }
        }.a),
    }, struct {
        a: struct {
            one: u64,
            two: u64,
        },
    }), null);
}
test "" {
    comptime expectEqual(testingImplements(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: var) ?[]const u8 {
                if (compare(struct { one: u64 }, Other)) |err| return err;
                return null;
            }
        }.a),
    }, struct {
        a: struct {
            one: u32,
            two: u64,
        },
    }), "base: Struct > a[custom] > custom: Struct > one: Int >: Types differ. Expected: u64, Got: u32.");
}
