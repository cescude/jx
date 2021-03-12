const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const json = std.json;
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if ( gpa.deinit() ) {
            std.log.warn("Memory leak detected!", .{});
        }
    }
    const allocator = &gpa.allocator;
    
    var j = &JsonIterator.init(allocator, std.io.getStdIn().reader());
    defer j.deinit();

    if (try j.next()) |start_token| {
        var path = ArrayList([]u8).init(allocator);
        defer path.deinit();

        switch (start_token) {
            .ObjectBegin => try processObject(allocator, j, &path, writeLine),
            .ArrayBegin => try processArray(allocator, j, &path, writeLine),
            else => 
                @panic("Not valid JSON"),
        }
    }
}

fn writeLine(prefix: []const u8, key: []const u8, val: []const u8) void {
    if (prefix.len > 0) {
        stdout.print("{s}.{s} {s}\n", .{prefix, key, val}) catch {};
    } else {
        stdout.print("{s} {s}\n", .{key, val}) catch {};
    }
}

const process_op = fn(prefix: []const u8, key: []const u8, val: []const u8) void;

const E = JsonIterator.Error || error{OutOfMemory};

fn processArray(a: *Allocator, j: *JsonIterator, path: *ArrayList([]u8), proc_fn: process_op) E!void {
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
            .String, .Number => |v| proc_fn(prefix, key, v),
            .Boolean         => |v| proc_fn(prefix, key, if (v) "true" else "false"),
            .Null            => proc_fn(prefix, key, "null"),
            .ObjectBegin => {
                try path.append(key);
                try processObject(a, j, path, proc_fn);
                _ = path.pop();
            },
            .ArrayBegin => {
                try path.append(key);
                try processArray(a, j, path, proc_fn);
                _ = path.pop();
            },
            .ObjectEnd, .ArrayEnd => @panic("Invalid JSON"),
        }

        index += 1;
    }
}

fn processObject(a: *Allocator, j: *JsonIterator, path: *ArrayList([]u8), proc_fn: process_op) E!void {

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
                .String, .Number => |v| proc_fn(prefix, key, v),
                .Boolean         => |v| proc_fn(prefix, key, if (v) "true" else "false"),
                .Null            => proc_fn(prefix, key, "null"),
                .ObjectBegin => {
                    try path.append(key);
                    try processObject(a, j, path, proc_fn);
                    _ = path.pop();
                },
                .ArrayBegin => {
                    try path.append(key);
                    try processArray(a, j, path, proc_fn);
                    _ = path.pop();
                },
                .ObjectEnd, .ArrayEnd => @panic("Invalid JSON"),
            }
        } else {
            @panic("Missing value in keyval pair");
        }
    }
}

const JsonIterator = struct {
    reader: std.fs.File.Reader = undefined,
    parser: json.StreamingParser = undefined,
    allocator: *Allocator = undefined,
    
    extra_token: ?json.Token = undefined,
    decoded_string: ?[]u8 = undefined,

    pub const Error =
        std.os.ReadError ||
        std.fmt.ParseIntError ||
        error{ParsingError,EndOfStream,OutOfMemory};

    pub const Token = union(enum) {
        ObjectBegin,
        ObjectEnd,
        ArrayBegin,
        ArrayEnd,
        Number: []const u8,
        String: []const u8,
        Boolean: bool,
        Null,
    };

    pub fn init(allocator: *Allocator, rdr: std.fs.File.Reader) JsonIterator {
        var iter: JsonIterator = undefined;
        iter.reader = rdr;
        iter.parser = json.StreamingParser.init();
        iter.allocator = allocator;
        
        iter.extra_token = null;
        iter.decoded_string = null;
        return iter;
    }

    pub fn deinit(self: *JsonIterator) void {
        if ( self.decoded_string ) |decoded| {
            self.allocator.free(decoded);
            self.decoded_string = null;
        }
    }

    fn convertToken(self: *JsonIterator, t: json.Token, input: []const u8) Error!?Token {
        switch (t) {
            .ObjectBegin => return Token.ObjectBegin,
            .ObjectEnd => return Token.ObjectEnd,
            .ArrayBegin => return Token.ArrayBegin,
            .ArrayEnd => return Token.ArrayEnd,
            .Number => |n| {
                const slice = n.slice(input, input.len-1);

                if (self.decoded_string) |decoded| {
                    self.allocator.free(decoded);
                }

                var decoded = try self.allocator.dupe(u8, slice);
                self.decoded_string = decoded;
                return Token{ .Number = decoded };
            },
            .String => |s| {
                const slice = s.slice(input, input.len-1);
                
                if ( self.decoded_string ) |decoded| {
                    self.allocator.free(decoded);
                }

                    // var decoded = try self.allocator.alloc(u8, s.decodedLength());
                    // errdefer self.allocator.free(decoded);
                    // try json.unescapeValidString(decoded, slice);
                    // self.decoded_string = decoded;
                    // return Token{ .String = decoded };

                var decoded = try self.allocator.dupe(u8, slice);
                self.decoded_string = decoded;
                return Token { .String = decoded };
            },
            .True => return Token{ .Boolean = true },
            .False => return Token{ .Boolean = false },
            .Null => return Token.Null,
        }
    }

    pub fn next(self: *JsonIterator) Error!?Token {

        var input = ArrayList(u8).init(self.allocator);
        defer input.deinit();
            
        if (self.extra_token) |token| {
            self.extra_token = null;
            // The extra token should never be a string or number (ergo
            // requiring a free)
            switch (token) {
                .String,.Number => @panic("Constraint violated!"),
                else =>
                    return self.convertToken(token, input.items),
            }
        }
        
        while (self.reader.readByte()) |byte| {
            input.append(byte) catch  return Error.ParsingError;
            
            var t0: ?json.Token = undefined;
            var t1: ?json.Token = undefined;

            self.parser.feed(byte, &t0, &t1) catch return Error.ParsingError;
            if (t0) |token| {
                self.extra_token = t1; // Might could be null, which is ok
                return self.convertToken(token, input.items);
            }
        } else |err| {
            if ( err != Error.EndOfStream ) {
                return err;
            }
        }

        if (self.parser.complete) {
            return null;
        }

        return Error.ParsingError;
    }
};
