const std = @import("std");
const explodeJson = @import("explode_json.zig");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

pub fn main() !void {

    // TODO: Figure out how to not include this if using the c_allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    const allocator = switch (std.builtin.mode) {
        .ReleaseFast => std.heap.c_allocator,
        else => &gpa.allocator,
    };

    var buffered_reader = std.io.bufferedReader(stdin);
    var br = buffered_reader.reader();

    var buffered_writer = std.io.bufferedWriter(stdout);
    defer buffered_writer.flush() catch {};
    var bw = buffered_writer.writer();

    const ExplodeProcessorType = explodeJson.Processor(@TypeOf(br), @TypeOf(bw));

    ExplodeProcessorType.process(allocator, &br, &bw) catch |e| switch (e) {
        error.InvalidTopLevel => std.debug.print("...TODO: Implode?\n", .{}),
        else => {}, //std.debug.print("{}\n", .{e}),
    };
}
