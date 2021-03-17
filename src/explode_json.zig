const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const JsonIterator = @import("json_iterator.zig").JsonIterator;
const JsonToken = @import("json_iterator.zig").Token;

fn LineWriter(comptime WriterType: type) type {
    return struct {
        writer: *const WriterType,

        const Self = @This();

        pub fn writeLine(self: *Self, prefix: []const u8, key: []const u8, val: []const u8, quote_val: bool) !void {

            // Looks like: <prefix>.<key>  <val>
            //         or: <prefix>.<key>  "<val>"
            //         or: <key>  <val>
            //         or: <key>  "<val>"

            if (prefix.len > 0) {
                try self.writer.print("{s}.", .{prefix});
            }

            try self.writer.print("{s}  ", .{key});

            if (quote_val) {
                try self.writer.print("\"{s}\"\n", .{val});
            } else {
                try self.writer.print("{s}\n", .{val});
            }
        }
    };
}

pub fn Processor(comptime ReaderType: type, comptime WriterType: type) type {
    const LineWriterType = LineWriter(WriterType);
    const JsonIteratorType = JsonIterator(ReaderType);

    return struct {
        pub fn process(a: *Allocator, reader: *ReaderType, writer: *const WriterType) !void {
            var w = LineWriterType{ .writer = writer };

            var j = JsonIteratorType.init(a, reader);
            defer j.deinit();

            var path = ArrayList([]u8).init(a);
            defer {
                for (path.items) |p| {
                    a.free(p);
                }
                path.deinit();
            }

            var indices = ArrayList(u32).init(a);
            defer indices.deinit();

            const State = enum { TopLevel, ParsingObject, ParsingArray };

            var states = ArrayList(State).init(a);
            defer states.deinit();

            try states.append(State.TopLevel);

            while (try j.next()) |token| {
                const current_state = states.items[states.items.len - 1];

                switch (current_state) {
                    .TopLevel => {
                        switch (token) {
                            .ObjectBegin => {
                                try states.append(State.ParsingObject);
                                try path.append(try a.dupe(u8, "root"));
                                continue;
                            },
                            .ArrayBegin => {
                                try states.append(State.ParsingArray);
                                try path.append(try a.dupe(u8, "root"));
                                try indices.append(0);
                                continue;
                            },
                            else => return error.NotJson,
                        }
                    },
                    .ParsingObject => {
                        if (token == JsonToken.ObjectEnd) {
                            _ = states.pop(); // TODO: could this fail?
                            a.free(path.pop());

                            if (path.items.len == 0) {
                                return error.EndOfTopLevel;
                            }

                            continue;
                        }

                        const prefix = try std.mem.join(a, ".", path.items[1..]);
                        defer a.free(prefix);

                        var key = try switch (token) {
                            .String => |s| a.dupe(u8, s),
                            else => @panic("Expected string for key in object!"),
                        };
                        defer a.free(key);

                        if (try j.next()) |val_token| {
                            switch (val_token) {
                                .String => |v| try w.writeLine(prefix, key, v, true),
                                .Number => |v| try w.writeLine(prefix, key, v, false),
                                .Boolean => |v| try w.writeLine(prefix, key, if (v) "true" else "false", false),
                                .Null => try w.writeLine(prefix, key, "null", false),
                                .ObjectBegin => {
                                    try states.append(State.ParsingObject);
                                    try path.append(try a.dupe(u8, key));
                                    continue;
                                },
                                .ArrayBegin => {
                                    try states.append(State.ParsingArray);
                                    try path.append(try a.dupe(u8, key));
                                    try indices.append(0);
                                    continue;
                                },
                                .ObjectEnd, .ArrayEnd => @panic("Invalid JSON"),
                            }
                        } else @panic("Missing val in keyval pair!");
                    },
                    .ParsingArray => {
                        if (token == JsonToken.ArrayEnd) {
                            _ = states.pop(); // TODO: could this fail?
                            a.free(path.pop());
                            _ = indices.pop(); // TODO: could this fail?

                            if (path.items.len == 0) {
                                return error.EndOfTopLevel;
                            }

                            continue;
                        }

                        var index = indices.pop();
                        try indices.append(index + 1);

                        const prefix = try std.mem.join(a, ".", path.items[1..]);
                        defer a.free(prefix);

                        var key = try std.fmt.allocPrint(a, "{d}", .{index});
                        defer a.free(key);

                        switch (token) {
                            .String => |v| try w.writeLine(prefix, key, v, true),
                            .Number => |v| try w.writeLine(prefix, key, v, false),
                            .Boolean => |v| try w.writeLine(prefix, key, if (v) "true" else "false", false),
                            .Null => try w.writeLine(prefix, key, "null", false),
                            .ObjectBegin => {
                                try states.append(State.ParsingObject);
                                try path.append(try a.dupe(u8, key));
                                continue;
                            },
                            .ArrayBegin => {
                                try states.append(State.ParsingArray);
                                try path.append(try a.dupe(u8, key));
                                try indices.append(0);
                                continue;
                            },
                            .ObjectEnd, .ArrayEnd => @panic("Invalid JSON"),
                        }
                    },
                }
            }
        }
    };
}
