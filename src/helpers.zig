const std = @import("std");

// these might be in the standard library already but I don't know how to describe what they do well enough to ask.
// nice to have things

fn interpolateInt(a: var, b: @TypeOf(a), progress: f64) @TypeOf(a) {
    const OO = @TypeOf(a);

    const floa = @intToFloat(f64, a);
    const flob = @intToFloat(f64, b);

    return @floatToInt(OO, floa + (flob - floa) * progress);
}

/// interpolate between two values. clamps to edges.
pub fn interpolate(a: var, b: @TypeOf(a), progress: f64) @TypeOf(a) {
    const Type = @TypeOf(a);
    if (progress < 0) return a;
    if (progress > 1) return b;

    switch (Type) {
        u8 => return interpolateInt(a, b, progress),
        i64 => return interpolateInt(a, b, progress),
        u64 => return interpolateInt(a, b, progress),
        else => {},
    }
    switch (@typeInfo(Type)) {
        .Int => @compileError("Currently only supports u8, i64, u64"),
        .Struct => |stru| {
            var res: Type = undefined;
            inline for (stru.fields) |field| {
                @field(res, field.name) = interpolate(@field(a, field.name), @field(b, field.name), progress);
            }
            return res;
        },
        else => @compileError("Unsupported"),
    }
}

test "interpolation" {
    std.testing.expectEqual(interpolate(@as(u64, 25), 27, 0.5), 26);
    std.testing.expectEqual(interpolate(@as(u8, 15), 0, 0.2), 12);
    const Kind = struct { a: u64 };
    std.testing.expectEqual(interpolate(Kind{ .a = 10 }, Kind{ .a = 8 }, 0.5), Kind{ .a = 9 });

    std.testing.expectEqual(interpolate(@as(i64, 923), 1200, 0.999999875), 1199);
    std.testing.expectEqual(interpolate(@as(i64, 923), 1200, 1.000421875), 1200);
}

fn ensureAllDefined(comptime ValuesType: type, comptime Enum: type) void {
    comptime {
        const fields = @typeInfo(Enum).Enum.fields;
        const fieldCount = fields.len;
        const valuesInfo = @typeInfo(ValuesType).Struct;

        var ensure: [fieldCount]bool = undefined;
        for (fields) |field, i| {
            ensure[i] = false;
        }
        for (valuesInfo.fields) |field| {
            // var val: Enum = std.meta.stringToEnum(Enum, field.name);
            var val: Enum = @field(Enum, field.name);
            const index = @enumToInt(val);
            if (ensure[index]) {
                @compileError("Duplicate key: " ++ field.name);
            }
            ensure[index] = true;
        }
        for (fields) |field, i| {
            if (!ensure[i]) {
                @compileLog(@intToEnum(Enum, i));
                @compileError("Missing key");
            }
        }
    }
}

/// A "struct" with enum keys
pub fn EnumArray(comptime Enum: type, comptime Value: type) type {
    const fields = @typeInfo(Enum).Enum.fields;
    const fieldCount = fields.len;
    return struct {
        const V = @This();
        data: [fieldCount]Value,

        pub fn init(values: var) V {
            const ValuesType = @TypeOf(values);
            const valuesInfo = @typeInfo(ValuesType).Struct;
            ensureAllDefined(ValuesType, Enum);

            var res: [fieldCount]Value = undefined;
            inline for (valuesInfo.fields) |field| {
                var val: Enum = @field(Enum, field.name);
                const index = @enumToInt(val);
                res[index] = @field(values, field.name);
            }
            return .{ .data = res };
        }
        pub fn initDefault(value: Value) V {
            var res: [fieldCount]Value = undefined;
            inline for (fields) |field, i| {
                res[i] = value;
            }
            return .{ .data = res };
        }

        pub fn get(arr: V, key: Enum) Value {
            return arr.data[@enumToInt(key)];
        }
        pub fn getPtr(arr: *V, key: Enum) *Value {
            return &arr.data[@enumToInt(key)];
        }
        pub fn set(arr: *V, key: Enum, value: Value) Value {
            var prev = arr.data[@enumToInt(key)];
            arr.data[@enumToInt(key)] = value;
            return prev;
        }
    };
}

// holds all the values of the union at once instead of just one value
pub fn UnionArray(comptime Union: type) type {
    const tinfo = @typeInfo(Union);
    const Enum = tinfo.Union.tag_type.?;
    const Value = Union;

    const fields = @typeInfo(Enum).Enum.fields;
    const fieldCount = fields.len;
    return struct {
        const V = @This();
        data: [fieldCount]Value,

        pub fn initUndefined() V {
            var res: [fieldCount]Value = undefined;
            return .{ .data = res };
        }

        pub fn get(arr: V, key: Enum) Value {
            return arr.data[@enumToInt(key)];
        }
        pub fn getPtr(arr: *V, key: Enum) *Value {
            return &arr.data[@enumToInt(key)];
        }
        pub fn set(arr: *V, value: Union) Value {
            const enumk = @enumToInt(std.meta.activeTag(value));
            defer arr.data[enumk] = value; // does this make the control flow more confusing? it's nice because I don't need a temporary name but it also could definitely be more confusing.
            return arr.data[enumk];
        }
    };
}

// comptime only
pub fn UnionCallReturnType(comptime Union: type, comptime method: []const u8) type {
    var res: ?type = null;
    for (@typeInfo(Union).Union.fields) |field| {
        const returnType = @typeInfo(@TypeOf(@field(field.field_type, method))).Fn.return_type orelse
            @compileError("Generic functions are not supported");
        if (res == null) res = returnType;
        if (res) |re| if (re != returnType) @compileError("Return types for fn " ++ method ++ " differ. First found " ++ @typeName(re) ++ ", then found " ++ @typeName(returnType));
    }
    return res orelse @panic("Union must have at least one field");
}

pub fn DePointer(comptime Type: type) type {
    return switch (@typeInfo(Type)) {
        .Pointer => |ptr| ptr.child,
        else => Type,
    };
}

pub fn unionCall(comptime Union: type, comptime method: []const u8, enumValue: @TagType(Union), args: var) UnionCallReturnType(Union, method) {
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);

    const callOpts: std.builtin.CallOptions = .{};
    inline for (typeInfo.fields) |field| {
        if (@enumToInt(enumValue) == field.enum_field.?.value) {
            return @call(callOpts, @field(field.field_type, method), args);
        }
    }
    @panic("Did not match any enum value");
}

pub fn unionCallReturnsThis(comptime Union: type, comptime method: []const u8, enumValue: @TagType(Union), args: var) Union {
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);

    const callOpts: std.builtin.CallOptions = .{};
    inline for (typeInfo.fields) |field| {
        if (@enumToInt(enumValue) == field.enum_field.?.value) {
            return @unionInit(Union, field.name, @call(callOpts, @field(field.field_type, method), args));
        }
    }
    @panic("Did not match any enum value");
}

// unionCallThis(*Union, "deinit")(someUnion, .{}) should work
// also is there any reason it needs to return a fn? why can't it be unionCallThis(someUnion, "deinit", .{})
pub fn unionCallThis(comptime method: []const u8, unionValue: var, args: var) UnionCallReturnType(DePointer(@TypeOf(unionValue)), method) {
    const isPtr = @typeInfo(@TypeOf(unionValue)) == .Pointer;
    const Union = DePointer(@TypeOf(unionValue));
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);

    const callOpts: std.builtin.CallOptions = .{};
    inline for (typeInfo.fields) |field| {
        if (@enumToInt(std.meta.activeTag(if (isPtr) unionValue.* else unionValue)) == field.enum_field.?.value) {
            return @call(callOpts, @field(field.field_type, method), .{if (isPtr) &@field(unionValue, field.name) else @field(unionValue, field.name)} ++ args);
        }
    }
    @panic("Did not match any enum value");
}

pub fn FieldType(comptime Container: type, comptime fieldName: []const u8) type {
    if (!@hasField(Container, fieldName)) @compileError("Container does not have field " ++ fieldName);
    switch (@typeInfo(Container)) {
        .Union => |uni| for (uni.fields) |field| {
            if (std.mem.eql(u8, field.name, fieldName)) return field.field_type;
        },
        .Struct => |stru| for (stru.fields) |field| {
            if (std.mem.eql(u8, field.name, fieldName)) return field.field_type;
        },
        else => @compileError("Must be Union | Struct"),
    }
    unreachable;
}

test "enum array" {
    const Enum = enum { One, Two, Three };
    const EnumArr = EnumArray(Enum, bool);

    var val = EnumArr.initDefault(false);
    std.testing.expect(!val.get(.One));
    std.testing.expect(!val.get(.Two));
    std.testing.expect(!val.get(.Three));

    _ = val.set(.Two, true);
    _ = val.set(.Three, true);

    std.testing.expect(!val.get(.One));
    std.testing.expect(val.get(.Two));
    std.testing.expect(val.get(.Three));
}

test "enum array initialization" {
    const Enum = enum { One, Two, Three };
    const EnumArr = EnumArray(Enum, bool);

    var val = EnumArr.init(.{ .One = true, .Two = false, .Three = true });
    std.testing.expect(val.get(.One));
    std.testing.expect(!val.get(.Two));
    std.testing.expect(val.get(.Three));
}

test "union array" {
    const Union = union(enum) { One: bool, Two: []const u8, Three: i64 };
    const UnionArr = UnionArray(Union);

    // var val = UnionArr.init(.{ .One = true, .Two = "hi!", .Three = 27 });
    var val = UnionArr.initUndefined();
    _ = val.set(.{ .One = true });
    _ = val.set(.{ .Two = "hi!" });
    _ = val.set(.{ .Three = 27 });

    std.testing.expect(val.get(.One).One);
    std.testing.expect(std.mem.eql(u8, val.get(.Two).Two, "hi!"));
    std.testing.expect(val.get(.Three).Three == 27);

    _ = val.set(.{ .Two = "bye!" });
    _ = val.set(.{ .Three = 54 });

    std.testing.expect(val.get(.One).One);
    std.testing.expect(std.mem.eql(u8, val.get(.Two).Two, "bye!"));
    std.testing.expect(val.get(.Three).Three == 54);
}

test "unionCall" {
    const Union = union(enum) {
        TwentyFive: struct {
            fn init() i64 {
                return 25;
            }
        }, FiftySix: struct {
            fn init() i64 {
                return 56;
            }
        }
    };
    std.testing.expectEqual(unionCall(Union, "init", .TwentyFive, .{}), 25);
    std.testing.expectEqual(unionCall(Union, "init", .FiftySix, .{}), 56);
}

test "unionCallReturnsThis" {
    const Union = union(enum) {
        number: Number,
        boolean: Boolean,
        const Number = struct {
            num: i64,
            pub fn init() Number {
                return .{ .num = 91 };
            }
        };
        const Boolean = struct {
            boo: bool,
            pub fn init() Boolean {
                return .{ .boo = true };
            }
        };
    };
    std.testing.expectEqual(unionCallReturnsThis(Union, "init", .number, .{}), Union{ .number = .{ .num = 91 } });
    std.testing.expectEqual(unionCallReturnsThis(Union, "init", .boolean, .{}), Union{ .boolean = .{ .boo = true } });
}

test "unionCallThis" {
    const Union = union(enum) {
        TwentyFive: struct {
            v: i32,
            v2: i64,
            fn print(value: @This()) i64 {
                return value.v2 + 25;
            }
        }, FiftySix: struct {
            v: i64,
            fn print(value: @This()) i64 {
                return value.v;
            }
        }
    };
    std.testing.expectEqual(unionCallThis("print", Union{ .TwentyFive = .{ .v = 5, .v2 = 10 } }, .{}), 35);
    std.testing.expectEqual(unionCallThis("print", Union{ .FiftySix = .{ .v = 28 } }, .{}), 28);
}

test "unionCallThis pointer arg" {
    const Union = union(enum) {
        TwentyFive: struct {
            v: i32,
            v2: i64,
            fn print(value: *@This()) i64 {
                return value.v2 + 25;
            }
        }, FiftySix: struct {
            v: i64,
            fn print(value: *@This()) i64 {
                return value.v;
            }
        }
    };
    var val = Union{ .TwentyFive = .{ .v = 5, .v2 = 10 } };
    std.testing.expectEqual(unionCallThis("print", &val, .{}), 35);
    val = Union{ .FiftySix = .{ .v = 28 } };
    std.testing.expectEqual(unionCallThis("print", &val, .{}), 28);
}

test "FieldType" {
    const Struct = struct {
        thing: u8,
        text: []const u8,
    };
    comptime std.testing.expectEqual(FieldType(Struct, "thing"), u8);
    comptime std.testing.expectEqual(FieldType(Struct, "text"), []const u8);
    const Union = union {
        a: f64,
        b: bool,
    };
    comptime std.testing.expectEqual(FieldType(Union, "a"), f64);
    comptime std.testing.expectEqual(FieldType(Union, "b"), bool);
}
