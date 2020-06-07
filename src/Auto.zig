const std = @import("std");
const gui = @import("gui.zig");
const help = @import("helpers.zig");

const Auto = @This();

alloc: *std.mem.Allocator,
items: ItemsMap,
id: gui.ID,

const ItemsMap = std.AutoHashMap(u64, struct { value: help.AnyPtr, deinit: DeinitFn });
const DeinitFn = fn (value: help.AnyPtr) void;

/// Intended for use with Auto.create
pub fn autoInit(event: *gui.ImEvent, alloc: *std.mem.Allocator) Auto {
    return .{
        .alloc = alloc,
        .items = ItemsMap.init(alloc),
        .id = event.newID(),
        // auto could store the id instead of the item storing it
        // sure, why not
    };
}

/// Intended for use with Auto.destroy
pub fn autoDeinit(auto: *Auto) void {
    var it = auto.items.iterator();
    while (it.next()) |next| {
        next.value.deinit(next.value.value);
        // since value is not comptime known, it needs a deinit fn
    }
    auto.items.deinit();
}

pub fn create(
    comptime Container: type,
    event: *gui.ImEvent,
    alloc: *std.mem.Allocator,
    remaining: var,
) Container {
    const ti = @typeInfo(Container).Struct;
    var result: Container = undefined;

    comptime var setFields: [ti.fields.len]bool = [_]bool{false} ** ti.fields.len;

    inline for (@typeInfo(@TypeOf(remaining)).Struct.fields) |rmfld| {
        comptime const i = for (ti.fields) |fld, i| {
            if (std.mem.eql(u8, fld.name, rmfld.name)) break i;
        } else @compileError("Field " ++ rmfld.name ++ " is not in " ++ @typeName(Container));
        comptime setFields[i] = true;
        comptime const curfld = ti.fields[i];
        @field(result, rmfld.name) = help.fixedCoerce(curfld.field_type, @field(remaining, rmfld.name));
    }
    inline for (ti.fields) |curfld, i| {
        if (setFields[i]) continue;
        if (curfld.default_value) |defltv| {
            @field(result, curfld.name) = defltv;
            continue;
        }
        if (!@hasDecl(curfld.field_type, "autoInit"))
            @compileError("Field `" ++ curfld.name ++ "` was not initialized.");
        @field(result, curfld.name) = curfld.field_type.autoInit(event, alloc);
    }

    return result;
}

pub fn destroy(selfptr: var, comptime fields: var) void {
    inline for (fields) |ft| {
        const fieldName = @tagName(ft);
        @field(selfptr, fieldName).autoDeinit();
    }
}

/// something must be a unique type every time otherwise the wrong id will be made!
/// don't use this in a loop (todo support loops)
pub fn new(auto: *Auto, initmethod: var, args: var) *@typeInfo(@TypeOf(initmethod)).Fn.return_type.? {
    const Type = @typeInfo(@TypeOf(initmethod)).Fn.return_type.?;
    const uniqueID = help.AnyPtr.typeID(struct {});
    if (auto.items.getValue(uniqueID)) |v| return v.value.readAs(Type);
    const allocated = auto.alloc.create(Type) catch @panic("oom not handled");
    const deinitfn: DeinitFn = struct {
        fn f(value: help.AnyPtr) void {
            value.readAs(Type).deinit();
        }
    }.f;
    allocated.* = @call(.{}, initmethod, args);
    if (auto.items.put(
        uniqueID,
        .{ .deinit = deinitfn, .value = help.AnyPtr.fromPtr(allocated) },
    ) catch @panic("oom not handled")) |_| @panic("duplicate insert (never)");
    return allocated;
}

// pub fn memo() yeah this is just react
