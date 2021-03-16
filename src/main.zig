const std = @import("std");
const explodeJson = @import("explode_json.zig");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.warn("Memory leak detected!", .{});
        }
    }
    const allocator = &gpa.allocator;

    var br = std.io.bufferedReader(stdin).reader();

    explodeJson.process(allocator, @TypeOf(br), br, @TypeOf(stdout), stdout) catch |e| switch (e) {
        error.InvalidTopLevel => std.debug.print("...Implode?\n", .{}),
        else => std.debug.print("{}\n", .{e}),
    };
}
