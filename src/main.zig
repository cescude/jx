const std = @import("std");
const explodeJson = @import("explode_json.zig");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.warn("Memory leak detected!", .{});
        }
    }
    const allocator = &gpa.allocator;

    var buffered_reader = std.io.bufferedReader(stdin);
    var br = buffered_reader.reader();

    var buffered_writer = std.io.bufferedWriter(stdout);
    defer buffered_writer.flush() catch {};
    var bw = buffered_writer.writer();

    comptime const ExplodeProcessorType = explodeJson.Processor(@TypeOf(br), @TypeOf(bw));

    ExplodeProcessorType.process(allocator, br, &bw) catch |e| switch (e) {
        error.InvalidTopLevel => std.debug.print("...Implode?\n", .{}),
        else => std.debug.print("{}\n", .{e}),
    };
}
