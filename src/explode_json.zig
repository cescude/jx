const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const JsonIterator = @import("json_iterator.zig").JsonIterator;

fn LineWriter(comptime WriterType: type) type {
    return struct {
        writer: *WriterType,

        const Self = @This();

        pub fn writeLine(self: *Self, prefix: []const u8, key: []const u8, val: []const u8) void {
            if (prefix.len > 0) {
                self.writer.print("{s}.{s}  {s}\n", .{ prefix, key, val }) catch {};
            } else {
                self.writer.print("{s}  {s}\n", .{ key, val }) catch {};
            }
        }
    };
}

pub fn Processor(comptime ReaderType: type, comptime WriterType: type) type {
    comptime const LineWriterType = LineWriter(WriterType);
    comptime const JsonIteratorType = JsonIterator(ReaderType);

    return struct {
        pub fn process(a: *Allocator, reader: *ReaderType, writer: *WriterType) !void {
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
                        if (token == JsonIteratorType.Token.ObjectEnd) {
                            _ = states.pop(); // TODO: could this fail?
                            a.free(path.pop());
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
                                .String, .Number => |v| w.writeLine(prefix, key, v),
                                .Boolean => |v| w.writeLine(prefix, key, if (v) "true" else "false"),
                                .Null => w.writeLine(prefix, key, "null"),
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
                        if (token == JsonIteratorType.Token.ArrayEnd) {
                            _ = states.pop(); // TODO: could this fail?
                            a.free(path.pop());
                            _ = indices.pop(); // TODO: could this fail?
                            continue;
                        }

                        var index = indices.pop();
                        try indices.append(index + 1);

                        const prefix = try std.mem.join(a, ".", path.items[1..]);
                        defer a.free(prefix);

                        var key = try std.fmt.allocPrint(a, "{d}", .{index});
                        defer a.free(key);

                        switch (token) {
                            .String, .Number => |v| w.writeLine(prefix, key, v),
                            .Boolean => |v| w.writeLine(prefix, key, if (v) "true" else "false"),
                            .Null => w.writeLine(prefix, key, "null"),
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
