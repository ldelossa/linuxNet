const log = @import("std").log;
const builtin = @import("builtin");

pub fn no_op(comptime format: []const u8, args: anytype) void {
    _ = args;
    _ = format;
}

pub fn get(comptime scope: @Type(.EnumLiteral)) type {
    if (builtin.is_test) {
        // return no-op
        return struct {
            pub const err = no_op;
            pub const warn = no_op;
            pub const info = no_op;
            pub const debug = no_op;
        };
    } else {
        return log.scoped(scope);
    }
}
