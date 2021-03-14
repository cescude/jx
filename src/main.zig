const std = @import("std");
const JsonIterator = @import("json_iterator.zig").JsonIterator;
const process = @import("explode_json.zig").process;
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

    var j = &JsonIterator.init(allocator, stdin);
    defer j.deinit();

    process(allocator, j, writeLine) catch |e| switch (e) {
        else => std.debug.print("{}\n", .{e}),
    };
}

fn writeLine(prefix: []const u8, key: []const u8, val: []const u8) void {
    if (prefix.len > 0) {
        stdout.print("{s}.{s}  {s}\n", .{ prefix, key, val }) catch {};
    } else {
        stdout.print("{s}  {s}\n", .{ key, val }) catch {};
    }
}
