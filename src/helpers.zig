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

pub fn Function(comptime Args: var, comptime Return: type) type {
    return struct {
        data: usize,
        call: fn (thisArg: usize, args: Args) Return,
    };
}
fn FunctionReturn(comptime Type: type) type {
    const fnData = @typeInfo(@TypeOf(Type.call)).Fn;
    if (fnData.is_generic) @compileLog("Generic functions are not allowed");
    const Args = blk: {
        var Args: []const type = &[_]type{};
        inline for (fnData.args) |arg| {
            Args = Args ++ [_]type{arg.arg_type.?};
        }
        break :blk Args;
    };
    const ReturnType = fnData.return_type.?;
    return struct {
        pub const All = Function(Args, ReturnType);
        pub const Args = Args;
        pub const ReturnType = ReturnType;
    };
}
pub fn function(data: var) FunctionReturn(@typeInfo(@TypeOf(data)).Pointer.child).All {
    const Type = @typeInfo(@TypeOf(data)).Pointer.child;
    comptime if (@TypeOf(data) != *const Type) unreachable;
    const FnReturn = FunctionReturn(Type);
    const CallFn = struct {
        pub fn call(thisArg: FnReturn.All, args: var) FnReturn.Return {
            return @call(data.call, .{@intToPtr(@TypeOf(data), thisArg.data)} ++ args);
        }
    }.call;
    @compileLog(FnReturn.All);
    return .{
        .data = @ptrToInt(data),
        .call = &CallFn,
    };
}
test "function" {
    // oops Unreachable at /deps/zig/src/analyze.cpp:5922 in type_requires_comptime. This is a bug in the Zig compiler.
    // zig compiler bug + something is wrong in my code
    if (false) {
        const Position = struct { x: i64, y: i64 };
        const testFn: Function(.{ f64, Position }, f32) = function(&struct {
            number: f64,
            pub fn call(data: *@This(), someValue: f64, argOne: Position) f32 {
                return @floatCast(f32, data.number + someValue + @intToFloat(f64, argOne.x) + @intToFloat(f64, argOne.y));
            }
        }{ .number = 35.6 });
        // function call is only supported within the lifetime of the data pointer
        // should it have an optional deinit method?
        std.testing.expectEqual(testFn.call(.{ 25, .{ .x = 56, .y = 25 } }), 25.6);
        std.testing.expectEqual(testFn.call(.{ 666, .{ .x = 12, .y = 4 } }), 25.6);
        // unfortunately there is no varargs or way to comptime set custom fn args so this has to be a .{array}
    }
}

/// the stdlib comptime hashmap is only created once and makes a "perfect hash"
/// so this works I guess.
///
/// comptime "hash"map. all accesses and sets are ~~O(1)~~ O(n)
pub fn ComptimeHashMap(comptime Key: type, comptime Value: type) type {
    const Item = struct { key: Key, value: Value };
    return struct {
        const HM = @This();
        items: []const Item,
        pub fn init() HM {
            return HM{
                .items = &[_]Item{},
            };
        }
        fn findIndex(comptime hm: HM, comptime key: Key) ?u64 {
            for (hm.items) |itm, i| {
                if (Key == []const u8) {
                    if (std.mem.eql(u8, itm.key, key))
                        return i;
                } else if (itm.key == key)
                    return i;
            }
            return null;
        }
        pub fn get(comptime hm: HM, comptime key: Key) ?Value {
            if (hm.findIndex(key)) |indx| return hm.items[indx].value;
            return null;
        }
        pub fn set(comptime hm: *HM, comptime key: Key, comptime value: Value) ?Value {
            if (hm.findIndex(key)) |prevIndex| {
                const prev = hm.items[prevIndex].value;
                // hm.items[prevIndex].value = value; // did you really think it would be that easy?
                var newItems: [hm.items.len]Item = undefined;
                for (hm.items) |prevItem, i| {
                    if (i == prevIndex) {
                        newItems[i] = Item{ .key = prevItem.key, .value = value };
                    } else {
                        newItems[i] = prevItem;
                    }
                }
                hm.items = &newItems;
                return prev;
            }
            hm.items = hm.items ++ &[_]Item{Item{ .key = key, .value = value }};
            return null;
        }
    };
}
// this can also be made using memoization and blk:
pub const TypeIDMap = struct {
    latestID: u64,
    hm: ComptimeHashMap(type, u64),
    infoStrings: []const []const u8,
    pub fn init() TypeIDMap {
        return .{
            .latestID = 0,
            .hm = ComptimeHashMap(type, u64).init(),
            .infoStrings = &[_][]const u8{"empty"},
        };
    }
    pub fn get(comptime tidm: *TypeIDMap, comptime Type: type) u64 {
        if (tidm.hm.get(Type)) |index| return index;
        tidm.latestID += 1;
        if (tidm.hm.set(Type, tidm.latestID)) |_| @compileError("never");
        tidm.infoStrings = tidm.infoStrings ++ &[_][]const u8{@typeName(Type)};
        // @compileLog("ID", tidm.latestID, "=", Type);
        return tidm.latestID;
    }
};
/// a pointer to arbitrary data. panics if attempted to be read as the wrong type.
pub const AnyPtr = comptime blk: {
    var typeIDMap = TypeIDMap.init();
    break :blk struct {
        pointer: usize,
        typeID: u64,
        pub fn fromPtr(value: var) AnyPtr {
            const ti = @typeInfo(@TypeOf(value));
            if (ti != .Pointer) @compileError("must be *ptr");
            if (ti.Pointer.size != .One) @compileError("must be ptr to one item");
            if (ti.Pointer.is_const) @compileError("const not yet allowed");
            const thisTypeID = comptime typeID(ti.Pointer.child);
            return .{ .pointer = @ptrToInt(value), .typeID = thisTypeID };
        }
        pub fn readAs(any: AnyPtr, comptime RV: type) *RV {
            const thisTypeID = comptime typeIDMap.get(RV);
            if (any.typeID != thisTypeID)
                std.debug.panic(
                    "\x1b[31mError!\x1b(B\x1b[m Item is of type {}, but was read as type {}.\n",
                    .{ typeIDMap.infoStrings[any.typeID], typeIDMap.infoStrings[thisTypeID] },
                );
            return @intToPtr(*RV, any.pointer);
        }
        pub fn typeID(comptime Type: type) u64 {
            return comptime typeIDMap.get(Type);
        }
        fn typeName(any: AnyPtr) []const u8 {
            return typeIDMap.infoStrings[any.typeID];
        }
    };
};

fn expectEqualStrings(str1: []const u8, str2: []const u8) void {
    if (std.mem.eql(u8, str1, str2)) return;
    std.debug.panic("\nExpected `{}`, got `{}`\n", .{ str1, str2 });
}

pub fn fixedCoerce(comptime Container: type, asl: var) Container {
    if (@typeInfo(@TypeOf(asl)) != .Struct) {
        return @as(Container, asl);
    }
    if (@TypeOf(asl) == Container) {
        return asl;
    }
    var result: Container = undefined;
    switch (@typeInfo(Container)) {
        .Struct => |ti| {
            comptime var setFields: [ti.fields.len]bool = [_]bool{false} ** ti.fields.len;
            inline for (@typeInfo(@TypeOf(asl)).Struct.fields) |rmfld| {
                comptime const i = for (ti.fields) |fld, i| {
                    if (std.mem.eql(u8, fld.name, rmfld.name)) break i;
                } else @compileError("Field " ++ rmfld.name ++ " is not in " ++ @typeName(Container));
                comptime setFields[i] = true;
                const field = ti.fields[i];
                @field(result, rmfld.name) = fixedCoerce(field.field_type, @field(asl, field.name));
            }
            comptime for (setFields) |bol, i| if (!bol) {
                comptime const field = ti.fields[i];
                if (field.default_value) |defv|
                    @field(result, field.name) = defv
                else
                    @compileError("Did not set field " ++ field.name);
            };
        },
        .Enum => @compileError("enum niy"),
        else => @compileError("cannot coerce anon struct literal to " ++ @typeName(Container)),
    }
    return result;
}

test "fixedCoerce" {
    const SomeValue = struct { b: u32 = 4, a: u16 };
    const OtherValue = struct { a: u16, b: u32 = 4 };
    std.testing.expectEqual(SomeValue{ .a = 5, .b = 4 }, fixedCoerce(SomeValue, .{ .a = 5 }));
    std.testing.expectEqual(SomeValue{ .a = 5, .b = 10 }, fixedCoerce(SomeValue, .{ .a = 5, .b = 10 }));
    std.testing.expectEqual(@as(u32, 25), fixedCoerce(u32, 25));
    std.testing.expectEqual(SomeValue{ .a = 5 }, SomeValue{ .a = 5 });

    // should fail:
    // unfortunately, since there is no way of detecting anon literals vs real structs, this may not be possible
    // *: maybe check if @TypeOf(&@as(@TypeOf(asl)).someField) is const? idk. that is a bug though
    //    that may be fixed in the future.
    std.testing.expectEqual(SomeValue{ .a = 5 }, fixedCoerce(SomeValue, OtherValue{ .a = 5 }));

    const InnerStruct = struct { b: u16 };
    const DoubleStruct = struct { a: InnerStruct };
    std.testing.expectEqual(DoubleStruct{ .a = InnerStruct{ .b = 10 } }, fixedCoerce(DoubleStruct, .{ .a = .{ .b = 10 } }));
}

test "anyptr" {
    var number: u32 = 25;
    var longlonglong: u64 = 25;
    var anyPtr = AnyPtr.fromPtr(&number);
    std.testing.expectEqual(AnyPtr.typeID(u32), AnyPtr.typeID(u32));
    var anyPtrLonglong = AnyPtr.fromPtr(&longlonglong);
    std.testing.expectEqual(AnyPtr.typeID(u64), AnyPtr.typeID(u64));

    // type names only work after they have been used at least once,
    // so typeName will probably be broken most of the time.
    expectEqualStrings("u32", anyPtr.typeName());
    expectEqualStrings("u64", anyPtrLonglong.typeName());
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
