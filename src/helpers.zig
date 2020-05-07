const std = @import("std");

// these might be in the standard library already but I don't know how to describe what they do well enough to ask.
// nice to have things
pub fn EnumArray(comptime Enum: type, comptime Value: type) type {
    const fields = @typeInfo(Enum).Enum.fields;
    const fieldCount = fields.len;
    return struct {
        const V = @This();
        data: [fieldCount]Value,
        pub fn init(values: var) V {
            const ValuesType = @TypeOf(values);
            const valuesInfo = @typeInfo(ValuesType).Struct;
            comptime {
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
        pub fn get(arr: V, key: var) Value {
            return arr.data[@enumToInt(key)];
        }
        pub fn getPtr(arr: *V, key: var) *Value {
            return &arr.data[@enumToInt(key)];
        }
        pub fn set(arr: *V, key: var, value: Value) Value {
            var prev = arr.data[@enumToInt(key)];
            arr.data[@enumToInt(key)] = value;
            return prev;
        }
    };
}
// holds all the values of the union at once instead of just one value
pub fn UnionArray(comptime Union: T) type {
    return struct {
        data: [@typeInfo(Enum).Enum.fields.len]Union,
    };
}