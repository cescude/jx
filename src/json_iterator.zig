const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const json = std.json;

pub const JsonIterator = struct {
    reader: std.fs.File.Reader = undefined,
    parser: json.StreamingParser = undefined,
    allocator: *Allocator = undefined,
    
    extra_token: ?json.Token = undefined,
    value_string: ?[]u8 = undefined,

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
        return .{
            .reader = rdr,
            .parser = json.StreamingParser.init(),
            .allocator = allocator,
            .extra_token = null,
            .value_string = null,
        };
    }

    pub fn deinit(self: *JsonIterator) void {
        if ( self.value_string ) |value| {
            self.allocator.free(value);
            self.value_string = null;
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

                if (self.value_string) |value| {
                    self.allocator.free(value);
                }

                var value = try self.allocator.dupe(u8, slice);
                self.value_string = value;
                return Token{ .Number = value };
            },
            .String => |s| {
                const slice = s.slice(input, input.len-1);
                
                if ( self.value_string ) |value| {
                    self.allocator.free(value);
                }

                    // var value = try self.allocator.alloc(u8, s.decodedLength());
                    // errdefer self.allocator.free(value);
                    // try json.unescapeValidString(value, slice);
                    // self.value_string = value;
                    // return Token{ .String = value };

                var value = try self.allocator.dupe(u8, slice);
                self.value_string = value;
                return Token { .String = value };
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
