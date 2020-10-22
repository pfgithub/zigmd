const std = @import("std");

pub const ImplCtx = struct {
    const Segment = struct {
        sourceType: ?type,
        name: []const u8,
        // flagCustom: bool,
    };

    segments: []const Segment = &[_]Segment{},

    pub fn join(comptime ctx: ImplCtx, comptime other: ImplCtx) ImplErr {
        var res = ctx;
        for (other.ctx.segments) |segment| {
            res = res.addSeg(segment);
        }
        return res;
    }

    pub fn addSeg(comptime ctx: ImplCtx, comptime segment: Segment) ImplCtx {
        return .{
            .segments = ctx.segments ++ [_]Segment{segment},
        };
    }
    pub fn add(comptime ctx: ImplCtx, comptime name: []const u8, comptime srcTyp: ?type) ImplCtx {
        return ctx.addSeg(Segment{
            .sourceType = srcTyp,
            .name = name,
        });
    }
    pub fn err(comptime ctx: ImplCtx, comptime msg: []const u8, comptime header: type, comptime impl: type) ImplErr {
        return .{
            .ctx = ctx,
            .err = msg,
            .header = header,
            .impl = impl,
        };
    }
};
pub const ImplErr = struct {
    ctx: ImplCtx,
    err: []const u8,
    header: type,
    impl: type,
};

const Memo = struct {
    const LaterDat = struct { Type: type };
    list: []const type = &[_]type{},
    later: []const LaterDat = &[_]LaterDat{},

    /// Check if a given type has been processed before. If not, mark it as processed.
    pub fn seen(comptime memo: *Memo, comptime Type: type) bool {
        for (memo.later) |Later| {
            if (Later.Type == Type) return true;
        }
        for (memo.list) |KnownType| {
            if (KnownType == Type) return true;
        }
        memo.list = memo.list ++ [_]type{Type};
        return false;
    }

    /// Note that a type will be processed in the future
    pub fn soon(comptime memo: *Memo, comptime Type: type) void {
        memo.later = memo.later ++ [_]LaterDat{LaterDat{ .Type = Type }};
    }

    /// Process a future type now
    pub fn now(comptime memo: *Memo, comptime Type: type) void {
        var newList: []const LaterDat = &[_]LaterDat{};
        var unseen = true;
        for (memo.later) |planned| {
            if (unseen and planned.Type == Type) {
                unseen = false;
                continue;
            }
            newList = newList ++ [_]LaterDat{planned};
        }
        memo.later = newList;
        if (unseen) @compileError("Cannot now something that is not soon");
    }

    /// Ensure memo did not skip any seen things
    pub fn done(comptime memo: *Memo) void {
        if (memo.later.len > 0) {
            for (memo.later) |lat| @compileLog(lat.Type);
            @compileError("Memo has items remaining");
        }
    }
};

const uhoh = @compileError("Fail!");

test "seen" {
    comptime {
        var memo: Memo = .{};
        if (memo.seen(u8)) uhoh;
        if (memo.seen(u16)) uhoh;
        if (!memo.seen(u8)) uhoh;
        const StructA = struct {};
        const StructB = struct {};
        if (memo.seen(StructA)) uhoh;
        if (memo.seen(StructB)) uhoh;
        if (!memo.seen(StructA)) uhoh;
        if (!memo.seen(StructB)) uhoh;
    }
}

test "seen soon" {
    comptime {
        var memo: Memo = .{};

        const Demo = struct {
            const A = struct {};
            const B = struct {};
            const C = struct {};
        };

        memo.soon(Demo.A);
        memo.soon(Demo.B);
        memo.soon(Demo.C);

        memo.now(Demo.A);
        if (memo.seen(Demo.A) != false) uhoh;
        if (memo.seen(Demo.A) != true) uhoh;
        if (memo.seen(Demo.B) != true) uhoh;
        if (memo.seen(Demo.C) != true) uhoh;

        {
            memo.soon(Demo.B);
            if (memo.seen(Demo.B) != true) uhoh;
            memo.now(Demo.B);
            if (memo.seen(Demo.B) != true) uhoh;
        }

        memo.now(Demo.B);
        if (memo.seen(Demo.A) != true) uhoh;
        if (memo.seen(Demo.B) != false) uhoh;
        if (memo.seen(Demo.B) != true) uhoh;
        if (memo.seen(Demo.C) != true) uhoh;

        memo.now(Demo.C);
        if (memo.seen(Demo.C) != false) uhoh;
        if (memo.seen(Demo.C) != true) uhoh;

        memo.done();
    }
}

fn prettyPrintError(comptime br: ImplErr) []const u8 {
    var result: []const u8 = "Types does not conform to spec\n" ++ br.err ++ "\n\nAt: ";
    for (br.ctx.segments) |seg, i| {
        if (i != 0) result = result ++ " > ";
        result = result ++ seg.name;
    }
    result = result ++ "\n";
    for (br.ctx.segments) |seg| {
        result = result ++ "\n  > " ++ seg.name;
        if (seg.sourceType) |srct| result = result ++ " :: " ++ @typeName(srct);
    }
    result = result ++ "\n\nHeader:         " ++ @typeName(br.header);
    result = result ++ "\nImplementation: " ++ @typeName(br.impl);
    result = result ++ "\n\n\x1B[31mError: " ++ br.err ++ "\x1B(B\x1B[m\n";
    return result;
}

pub fn conformsTo(comptime Header: type, comptime Implementation: type) void {
    if (testingImplements(Header, Implementation)) |err|
        @compileError(prettyPrintError(err));
}
pub fn conformsToBool(comptime Header: type, comptime Implementation: type) bool {
    if (testingImplements(Header, Implementation)) |err|
        return false
    else
        return true;
}
fn testingImplements(comptime Header: type, comptime Implementation: type) ?ImplErr {
    var memo: Memo = .{};
    var res = implements(Header, Implementation, ImplCtx{}, &memo);
    if (res == null)
        memo.done();
    return res;
}

fn testingFormatError(comptime br: ImplErr) []const u8 {
    var result: []const u8 = "";
    for (br.ctx.segments) |seg| {
        if (result.len != 0) result = result ++ " > ";
        const tag = if (seg.sourceType) |st| @tagName(@as(@TagType(@TypeOf(@typeInfo(st))), @typeInfo(st))) else "?";
        result = result ++ seg.name ++ ": " ++ tag;
    }
    if (result.len != 0) result = result ++ " >: ";
    result = result ++ br.err;
    return result;
}

fn expectEqual(comptime brv: ?ImplErr, comptime a: []const u8) void {
    const b: ?[]const u8 = if (brv) |br| testingFormatError(br) else null;
    if (b == null)
        @compileError("Expected `" ++ a ++ "`, got null");
    if (!std.mem.eql(u8, a, b.?))
        @compileError("Expected `" ++ a ++ "`, got `" ++ b.? ++ "`");
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
    comptime context: ImplCtx,
    comptime memo: *Memo,
) ?ImplErr {
    if (Header == Implementation) return null;
    if (memo.seen(memoHeaderImpl(Header, Implementation)))
        return null;

    const header = @typeInfo(Header);
    const implementation = @typeInfo(Implementation);

    if ((header == .Struct or header == .Union or header == .Enum) and @hasDecl(Header, "__custom_type_compare")) {
        const namedContext = context.add("[custom]", Header.__SOURCE_LOCATION);
        const compare = struct {
            fn a(comptime H: type, comptime I: type, comptime j: ImplCtx) ?ImplErr {
                return implements(H, I, j, memo);
            }
        }.a;
        if (Header.__custom_type_compare(
            Implementation,
            compare,
            namedContext,
        )) |err|
            return err;
        return null;
    }

    const headerTag = @as(@TagType(@TypeOf(header)), header);
    const implementationTag = @as(@TagType(@TypeOf(implementation)), implementation);
    if (headerTag != implementationTag)
        return context.err("Implementation has incorrect type (expected " ++ @tagName(headerTag) ++ ", got " ++ @tagName(implementationTag) ++ ")", Header, Implementation);

    const namedContext = context;

    switch (header) {
        .Struct => if (structImplements(Header, Implementation, namedContext, memo)) |err|
            return err,
        .Int, .Float, .Bool => {
            if (Header != Implementation) {
                return namedContext.err(
                    "Types differ. Expected: " ++ @typeName(Header) ++ ", Got: " ++ @typeName(Implementation) ++ ".",
                    Header,
                    Implementation,
                );
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
        else => return namedContext.err("Not supported yet: " ++ @tagName(headerTag), Header, Implementation),
    }
    return null;
}

fn errorSetImplements(
    comptime Header: type,
    comptime Implementation: type,
    context: ImplCtx,
    comptime memo: *Memo,
) ?ImplErr {
    const header = @typeInfo(Header).ErrorSet orelse
        return context.err("? TODO investigate", Header, Implementation);
    const impl = @typeInfo(Implementation).ErrorSet orelse
        return context.err("TODO investigate", Header, Implementation);

    if (header.len == 0 and impl.len == 0)
        return context.err("Empty error sets are not supported due to potential compiler bugs. Make sure the implementation has at least one error.", Header, Implementation);

    if (Header != Implementation) {
        for (header) |errv| {
            for (impl) |errc| {
                if (errv.value == errc.value) break;
            } else return context.err("Implementation missing error `" ++ errv.name ++ "`", Header, Implementation);
        }
        for (impl) |errv| {
            for (header) |errc| {
                if (errv.value == errc.value) break;
            } else return context.err("> Implementation has extra error `" ++ errv.name ++ "`", Header, Implementation);
        }
        // ok, error sets are the same.
    }

    return null;
}
fn errorUnionImplements(
    comptime Header: type,
    comptime Implementation: type,
    context: ImplCtx,
    comptime memo: *Memo,
) ?ImplErr {
    // these cannot be passed as args because of a compiler bug
    const header = @typeInfo(Header).ErrorUnion;
    const impl = @typeInfo(Implementation).ErrorUnion;

    if (implements(header.error_set, impl.error_set, context.add("ErrorSet!..", header.error_set), memo)) |err|
        return err;
    if (implements(header.payload, impl.payload, context.add("..!Payload", header.payload), memo)) |err|
        return err;

    return null;
}

fn pointerImplements(
    comptime Header: type,
    comptime Implementation: type,
    context: ImplCtx,
    comptime memo: *Memo,
) ?ImplErr {
    // these cannot be passed as args because of a compiler bug
    const header = @typeInfo(Header).Pointer;
    const impl = @typeInfo(Implementation).Pointer;

    const namedCtx = context.add(".*", header.child);
    if (header.is_volatile) return namedCtx.add("Pointer volatility is not supported yet.");
    if (impl.is_volatile) return namedCtx.err("Expected not volatile.", Header, Implementation);
    // ignoring sentinel for now, it looks complicated
    if (header.is_const != impl.is_const) return namedCtx.err("Expected constness {}, got {}.", Header, Implementation);
    // if (header.alignment != impl.alignment) return context.err("Expected align({}), got align({})."); // does not appear to be useful
    if (header.is_allowzero != impl.is_allowzero) return namedCtx.err("Expected allowzero {}, got {}.", Header, Implementation);

    if (implements(header.child, impl.child, namedCtx, memo)) |err|
        return err;

    return null;
}

fn fnImplements(
    comptime Header: type,
    comptime Implementation: type,
    context: ImplCtx,
    comptime memo: *Memo,
) ?ImplErr {
    const header = @typeInfo(Header).Fn;
    const impl = @typeInfo(Implementation).Fn;

    if (header.is_generic) return context.err("Generic functions are not supported yet.", Header, Implementation);
    if (header.is_var_args) return context.err("VarArgs functions are not supported yet.", Header, Implementation);
    if (impl.is_generic) return context.err("Expected non-generic, got generic", Header, Implementation);
    if (impl.is_var_args) return context.err("Expected non-varargs, got varargs.", Header, Implementation);
    if (header.calling_convention != impl.calling_convention) return context.err("Wrong calling convention.", Header, Implementation);

    if (implements(header.return_type.?, impl.return_type.?, context.add("return", header.return_type.?), memo)) |err|
        return err;

    if (header.args.len != impl.args.len) return context.err("Expected {} arguments, got {}.", Header, Implementation);
    for (header.args) |headerarg, i| {
        const implarg = impl.args[i];

        var buf = [_]u8{0} ** 100;
        const res = std.fmt.bufPrint(&buf, "args[{}]", .{i}) catch @compileError("buffer out of space");
        const argContext = context.add(res, headerarg.arg_type);

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
    context: ImplCtx,
    comptime memo: *Memo,
) ?ImplErr {
    const header = @typeInfo(Header).Struct;
    const implementation = @typeInfo(Implementation).Struct;

    for (header.decls) |decl| {
        if (!decl.is_pub) continue;
        if (decl.name.len >= 4 and std.mem.eql(u8, decl.name[0..4], "__h_")) continue;

        const namedContext = context.add("decl " ++ decl.name, switch (decl.data) {
            .Type, .Var => |typ| typ,
            .Fn => |fndecl| fndecl.fn_type,
        });

        // ensure implementation has decl
        if (!@hasDecl(Implementation, decl.name))
            return namedContext.err("Implementation is missing declaration.", Header, Implementation);

        // using for as a find with break and else doesn't seem to be working at comptime, so this works as an alternative
        const impldecl = blk: {
            for (implementation.decls) |idecl, i| {
                if (std.mem.eql(u8, decl.name, idecl.name))
                    break :blk idecl;
            }
            return namedContext.err("Implementation is missing declaration.", Header, Implementation);
        };

        if (!impldecl.is_pub) return namedContext.err("Implementation declaration is private.", Header, Implementation);

        const headerDataType = @as(@TagType(@TypeOf(decl.data)), decl.data);
        const implDataType = @as(@TagType(@TypeOf(impldecl.data)), impldecl.data);

        if (headerDataType != implDataType)
            return namedContext.err("DataTypes differ. Expected: " ++ @tagName(headerDataType) ++ ", got " ++ @tagName(implDataType), Header, Implementation);

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
            .Var => |typ| if (implements(typ, @TypeOf(@field(Implementation, decl.name)), namedContext, memo)) |err| return err,
        }
    }
    for (implementation.decls) |decl| {
        if (!@hasDecl(Header, decl.name) and decl.is_pub and !@hasDecl(Header, "__h_ALLOW_EXTRA"))
            return context.err("Header has extra disallowed declaration `pub " ++ decl.name ++ "`", Header, Implementation);
    }

    for (header.fields) |field| {
        // ensure implementation has field
        if (!@hasField(Implementation, field.name))
            return context.err("Implementation is missing field `" ++ field.name ++ "`", Header, Implementation);
        for (implementation.fields) |implfld| {
            if (!std.mem.eql(u8, field.name, implfld.name)) continue;

            if (implements(field.field_type, implfld.field_type, context.add(field.name, field.field_type), memo)) |err| return err;
        }
    }
    return null;
}

pub fn CustomTypeCompare(comptime comparisonFn: fn (type, anytype, ImplCtx) ?ImplErr) type {
    return struct {
        const __SOURCE_LOCATION = @TypeOf(comparisonFn);
        const __custom_type_compare = comparisonFn;
    };
}

test "extra declaration" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        pub const B = u32;
    }), "Header has extra disallowed declaration `pub B`");
}

test "extra private declaration ok" {
    comptime conformsTo(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
        const B = u32;
    });
}

test "missing declaration" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const B = u32;
    }), "decl A: Int >: Implementation is missing declaration.");
}

test "integer different" {
    comptime expectEqual(testingImplements(struct {
        pub const A = u64;
    }, struct {
        pub const A = u32;
    }), "decl A: Int >: Types differ. Expected: u64, Got: u32.");
}

test "integer equivalent" {
    comptime conformsTo(struct {
        pub const A = u64;
    }, struct {
        pub const A = u64;
    });
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
    }), "Implementation is missing field `c`");
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
    }), "b: Int >: Types differ. Expected: u64, Got: u32.");
}

test "fields equivalent + extra private" {
    comptime conformsTo(struct {
        pub const A = u64;
        a: A,
        b: u32,
    }, struct {
        pub const A = u64;
        a: A,
        b: u32,
        private_member: f64,
    });
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
    }), "decl a: Fn > return: Struct >: Implementation is missing field `typ`");
}

test "fn equivalent" {
    comptime conformsTo(struct {
        pub const Struct = struct { typ: u64 };
        pub fn a(arg: Struct, arg2: u64, arg3: bool) Struct {
            return undefined;
        }
    }, struct {
        pub const Struct = struct { typ: u64, extra_private: u64 };
        pub fn a(arg: Struct, arg2: u64, arg3: bool) Struct {
            return undefined;
        }
    });
}

test "fields" {
    comptime expectEqual(testingImplements(struct {
        q: u64,
    }, struct {
        q: u32,
    }), "q: Int >: Types differ. Expected: u64, Got: u32.");
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
    }), "decl a: Fn > args[1]: Struct > typ: Int >: Types differ. Expected: u64, Got: u32.");
}

test "basic recursion" {
    comptime conformsTo(struct {
        pub const Recursion = struct {
            pub const This = Recursion;
        };
    }, struct {
        pub const Recursion = struct {
            pub const This = Recursion;
        };
    });
}
test "fn this arg recursion" {
    comptime conformsTo(struct {
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
    });
}
test "" {
    comptime expectEqual(testingImplements(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: anytype, comptime ctx: ImplCtx) ?ImplErr {
                return if (Other == u64) null else ctx.err("Expected u64", @This(), Other);
            }
        }.a),
    }, struct {
        a: u32,
    }), "a: Struct > [custom]: Fn >: Expected u64");
}
test "" {
    comptime conformsTo(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: anytype, comptime ctx: ImplCtx) ?ImplErr {
                return if (Other == u64) null else ctx.err("Expected u64", @This(), Other);
            }
        }.a),
    }, struct {
        a: u64,
    });
}
test "" {
    comptime conformsTo(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: anytype, comptime ctx: ImplCtx) ?ImplErr {
                if (compare(struct { one: u64 }, Other, ctx)) |err| return err;
                return null;
            }
        }.a),
    }, struct {
        a: struct {
            one: u64,
            two: u64,
        },
    });
}
test "" {
    comptime expectEqual(testingImplements(struct {
        a: CustomTypeCompare(struct {
            pub fn a(comptime Other: type, comptime compare: anytype, comptime ctx: ImplCtx) ?ImplErr {
                if (compare(struct { one: u64 }, Other, ctx)) |err| return err;
                return null;
            }
        }.a),
    }, struct {
        a: struct {
            one: u32,
            two: u64,
        },
    }), "a: Struct > [custom]: Fn > one: Int >: Types differ. Expected: u64, Got: u32.");
}

/// UniqueType can only be header matched once!
pub fn UniqueType(nomemo: anytype) type {
    var saved: ?type = null;
    return CustomTypeCompare(struct {
        pub fn a(comptime Other: type, comptime compare: anytype, comptime ctx: ImplCtx) ?ImplErr {
            if (saved == null) {
                saved = Other;
                return null;
            }
            if (saved) |s|
                if (s != Other)
                    return ctx.err("Expected, got.", s, Other);
            return null;
        }
    }.a);
}

pub const AnyType = CustomTypeCompare(struct {
    pub fn a(comptime Other: type, comptime compare: anytype, comptime ctx: ImplCtx) ?ImplErr {
        return null;
    }
}.a);

test "" {
    comptime expectEqual(testingImplements(struct {
        pub const A = UniqueType(.{});
        pub const B = UniqueType(.{});
        pub const C = A;
    }, struct {
        pub const A = struct {};
        pub const B = struct {};
        pub const C = struct {};
    }), "decl A: Struct > [custom]: Fn >: Expected, got.");
    comptime conformsTo(struct {
        pub const A = UniqueType(.{});
        pub const B = UniqueType(.{});
        pub const C = A;
    }, struct {
        pub const A = struct {};
        pub const B = struct {};
        pub const C = A;
    });
}

// TODO for this. instead of implements happening immediately, it should:
// - add this call to a list
// The main caller passes in a list and
// - while list !empty
// -   realCheckImplements(item)
// oh and I guess it would have to loop and find the lowest thing to do each tick
// this sounds overcomplicated and unnecessary

// test "shallowest path" {
//     comptime expectEqual(testingImplements(struct {
//         pub const A = struct {
//             b: B,
//         };
//         pub const B = struct {
//             num: i64,
//         };
//     }, struct {
//         pub const A = struct {
//             b: B,
//         };
//         pub const B = struct {
//             num: u64,
//         };
//     }), "decl B: Struct > num: Int >: Types differ. Expected: i64, Got: u64.");
// }
