const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const JsonIterator = @import("json_iterator.zig").JsonIterator;

const callback_fn = fn (prefix: []const u8, key: []const u8, val: []const u8) void;

// For recursive functions, can't infer the error type
const Error = JsonIterator.Error || error{ InvalidStart, OutOfMemory };

pub fn process(a: *Allocator, j: *JsonIterator, cb: callback_fn) !void {
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
                    else => @panic("TODO: Handle free-floating vals"),
                }
            },
            .ParsingObject => {
                if (token == JsonIterator.Token.ObjectEnd) {
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
                        .String, .Number => |v| cb(prefix, key, v),
                        .Boolean => |v| cb(prefix, key, if (v) "true" else "false"),
                        .Null => cb(prefix, key, "null"),
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
                if (token == JsonIterator.Token.ArrayEnd) {
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
                    .String, .Number => |v| cb(prefix, key, v),
                    .Boolean => |v| cb(prefix, key, if (v) "true" else "false"),
                    .Null => cb(prefix, key, "null"),
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
