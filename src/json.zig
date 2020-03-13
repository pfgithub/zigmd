test "automatic json deserialization" {
    const JsonType = struct {
        structField: enum { enumValue1, enumValue2 }
    };
    const jsonin = "{\"structField\":\"enumValue1\"}";
    const res = parseJSON(JsonType, jsonin);
    assert(res.structField == .enumValue1);
}

// std.json might already do this stuff
// actually maybe not, I don't see any tests for tagged enums with structs

/// test "parse into tagged union" {
///     {
///         const T = union(enum) {
///             int: i32,
///             float: f64,
///             string: []const u8,
///         };
///         testing.expectEqual(T{ .float = 1.5 }, try parse(T, &TokenStream.init("1.5"), ParseOptions{}));
///     }
pub fn nothing() void {}
