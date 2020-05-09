const std = @import("std");

// these might be in the standard library already but I don't know how to describe what they do well enough to ask.
// nice to have things

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
fn unionCallReturnType(comptime Union: type, comptime method: []const u8) type {
    var res: ?type = null;
    for (@typeInfo(Union).Union.fields) |field| {
        const returnType = @typeInfo(@TypeOf(@field(field.field_type, method))).Fn.return_type orelse
            @compileError("Generic functions are not supported");
        if (res == null) res = returnType;
        if (res) |re| if (re != returnType) @compileError("Return types for fn " ++ method ++ " differ. First found " ++ @typeName(re) ++ ", then found " ++ @typeName(returnType));
    }
    return res orelse @panic("Union must have at least one field");
}

pub fn unionCall(comptime Union: type, comptime method: []const u8) comptime fn (@TagType(Union), var) unionCallReturnType(Union, method) {
    const typeInfo = @typeInfo(Union).Union;
    const TagType = std.meta.TagType(Union);
    const ReturnType = comptime unionCallReturnType(Union, method);

    return struct {
        fn call(enumValue: TagType, args: var) ReturnType {
            const callOpts: std.builtin.CallOptions = .{};
            inline for (typeInfo.fields) |field| {
                if (@enumToInt(enumValue) == field.enum_field.?.value) {
                    return @call(callOpts, @field(field.field_type, method), args);
                }
            }
            @panic("Did not match any enum value");
        }
    }.call;
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
    std.testing.expectEqual(unionCall(Union, "init")(.TwentyFive, .{}), 25);
    std.testing.expectEqual(unionCall(Union, "init")(.FiftySix, .{}), 56);
}
