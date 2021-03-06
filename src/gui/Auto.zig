const std = @import("std");

const gui = @import("../gui.zig");
const help = @import("../helpers.zig");
const header_match = @import("../header_match.zig");

const Auto = @This();

alloc: *std.mem.Allocator,
items: ItemsMap,
id: gui.ID,

const ItemsMap = std.AutoHashMap(u64, struct { value: help.AnyPtr, destroy: DestroyFn });
const DestroyFn = fn (value: help.AnyPtr, alloc: *std.mem.Allocator) void;

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
        next.value.destroy(next.value.value, auto.alloc);
        // since value is not comptime known, it needs a deinit fn
    }
    auto.items.deinit();
}

const AutoInitHeader = struct {
    pub fn autoInit(event: *gui.ImEvent, alloc: *std.mem.Allocator) @This() {
        return undefined;
    }
    pub const __h_ALLOW_EXTRA = true;
};
const ImevInitHeader = struct {
    pub fn init(event: *gui.ImEvent) @This() {
        return undefined;
    }
    pub const __h_ALLOW_EXTRA = true;
};
const ImevInitAllocHeader = struct {
    pub fn init(event: *gui.ImEvent, alloc: *std.mem.Allocator) @This() {
        return undefined;
    }
    pub const __h_ALLOW_EXTRA = true;
};

pub fn autoInitAnyThing(comptime Thing: type, comptime fieldName: []const u8, event: *gui.ImEvent, alloc: *std.mem.Allocator) Thing {
    return if (comptime header_match.conformsToBool(AutoInitHeader, Thing))
        Thing.autoInit(event, alloc)
    else if (comptime header_match.conformsToBool(ImevInitHeader, Thing))
        Thing.init(event)
    else if (comptime header_match.conformsToBool(ImevInitAllocHeader, Thing))
        Thing.init(event, alloc)
    else {
        // comptime header_match.conformsTo(AutoInitHeader, curfld.field_type);
        @compileError("Field `" ++ fieldName ++ "` was not initialized.");
    };
}

pub fn create(
    comptime Container: type,
    event: *gui.ImEvent,
    alloc: *std.mem.Allocator,
    remaining: anytype,
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
        @field(result, curfld.name) = autoInitAnyThing(curfld.field_type, curfld.name, event, alloc);
    }

    return result;
}

// instead of the current thing, what if we looped over all and autoDeinitted
// fields that would be user deinitted or did not need deinitting would be
// provided as a list
pub fn destroy(selfptr: anytype, comptime fields: anytype) void {
    inline for (fields) |ft| {
        const fieldName = @tagName(ft);
        const FieldType = help.FieldType(std.meta.Child(@TypeOf(selfptr)), fieldName);
        if (@hasDecl(FieldType, "autoDeinit"))
            @field(selfptr, fieldName).autoDeinit()
        else if (@hasDecl(FieldType, "deinit"))
            @field(selfptr, fieldName).deinit()
        else
            @compileError(@typeName(FieldType) ++ " does not have a deinit fn");
    }
}

/// something must be a unique type every time otherwise the wrong id will be made!
/// don't use this in a loop (todo support loops)
pub fn new(auto: *Auto, initmethod: anytype, args: anytype) *@typeInfo(@TypeOf(initmethod)).Fn.return_type.? {
    const Type = @typeInfo(@TypeOf(initmethod)).Fn.return_type.?;
    const uniqueID = help.AnyPtr.typeID(struct {});
    if (auto.items.get(uniqueID)) |v| return v.value.readAs(Type);
    const allocated = auto.alloc.create(Type) catch @panic("oom not handled");
    const destroyfn: DestroyFn = struct {
        fn f(value: help.AnyPtr, alloc: *std.mem.Allocator) void {
            const vv = value.readAs(Type);
            vv.deinit();
            alloc.destroy(vv);
        }
    }.f;
    allocated.* = @call(.{}, initmethod, args);
    auto.items.putNoClobber(
        uniqueID,
        .{ .destroy = destroyfn, .value = help.AnyPtr.fromPtr(allocated) },
    ) catch @panic("oom not handled");
    return allocated;
}

// pub fn memo() yeah this is just react
