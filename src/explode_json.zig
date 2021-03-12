const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const JsonIterator = @import("json_iterator.zig").JsonIterator;

const callback_fn = fn(prefix: []const u8, key: []const u8, val: []const u8) void;

// For recursive functions, can't infer the error type
const Error = JsonIterator.Error || error{InvalidStart,OutOfMemory};

pub fn explodeJson(a: *Allocator, j: *JsonIterator, cb: callback_fn) Error!void {
    if (try j.next()) |start_token| {
        var path = ArrayList([]u8).init(a);
        defer path.deinit();

        switch (start_token) {
            .ObjectBegin => try processObject(a, j, &path, cb),
            .ArrayBegin => try processArray(a, j, &path, cb),
            else => return Error.InvalidStart,
        }
    }
}

fn processArray(a: *Allocator, j: *JsonIterator, path: *ArrayList([]u8), cb: callback_fn) Error!void {
    var prefix = try std.mem.join(a, ".", path.items);
    defer a.free(prefix);

    var index: u64 = 0;
    while (try j.next()) |val_token| {

        if (val_token == JsonIterator.Token.ArrayEnd) {
            return;
        }

        var key = try std.fmt.allocPrint(a, "{d}", .{index});
        defer a.free(key);

        switch (val_token) {
            .String, .Number => |v| cb(prefix, key, v),
            .Boolean         => |v| cb(prefix, key, if (v) "true" else "false"),
            .Null            => cb(prefix, key, "null"),
            .ObjectBegin => {
                try path.append(key);
                try processObject(a, j, path, cb);
                _ = path.pop();
            },
            .ArrayBegin => {
                try path.append(key);
                try processArray(a, j, path, cb);
                _ = path.pop();
            },
            .ObjectEnd, .ArrayEnd => @panic("Invalid JSON"),
        }

        index += 1;
    }
}

fn processObject(a: *Allocator, j: *JsonIterator, path: *ArrayList([]u8), cb: callback_fn) Error!void {

    var prefix = try std.mem.join(a, ".", path.items);
    defer a.free(prefix);
    
    while (try j.next()) |key_token| {

        if (key_token == JsonIterator.Token.ObjectEnd) {
            return;
        }
        
        // Objects are pairs of key/vals until we hit the end
        
        var key: []u8 = try switch (key_token) {
            .String => |str| a.dupe(u8, str),
            else => @panic("Expected string for key in object"),
        };
        defer a.free(key);
        
        if (try j.next()) |val_token| {
            switch (val_token) {
                .String, .Number => |v| cb(prefix, key, v),
                .Boolean         => |v| cb(prefix, key, if (v) "true" else "false"),
                .Null            => cb(prefix, key, "null"),
                .ObjectBegin => {
                    try path.append(key);
                    try processObject(a, j, path, cb);
                    _ = path.pop();
                },
                .ArrayBegin => {
                    try path.append(key);
                    try processArray(a, j, path, cb);
                    _ = path.pop();
                },
                .ObjectEnd, .ArrayEnd => @panic("Invalid JSON"),
            }
        } else {
            @panic("Missing value in keyval pair");
        }
    }
}
