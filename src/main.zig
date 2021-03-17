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

    const ExplodeProcessorType = explodeJson.Processor(@TypeOf(br), @TypeOf(stdout));

    while (true) {
        ExplodeProcessorType.process(allocator, &br, &stdout) catch |e| switch (e) {
            // Support reading multiple objects from the same stream
            error.EndOfTopLevel => continue,

            // Support skipping over garbage data, for example if tailing data
            // that's missing the top of the JSON.
            //
            //     tail -F items.json | jx
            //
            error.NotJson, error.InvalidTopLevel => continue,
            error.EndOfStream => break,
            else => {
                std.debug.print("ERROR: {}\n", .{e});
                continue;
            },
        };
    }
}
