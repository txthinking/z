const std = @import("std");

pub fn send(allocator: std.mem.Allocator, in: []u8) !struct { b: []u8, n: usize } {
    const addr = try std.net.Address.parseIp6("::1", 2);
    const stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();
    try stream.writeAll(in);
    try stream.writeAll("\n");
    var b = try allocator.alloc(u8, 1024 * 4);
    errdefer allocator.free(b);
    var l: usize = 0;
    while (true) {
        const n = try stream.read(b[l..]);
        if (n == 0) {
            break;
        }
        l += n;
        if (std.mem.endsWith(u8, b[0..l], "welovetxthinking")) {
            break;
        }
        if (b.len == l) {
            const ok = allocator.resize(b, b.len + 1024 * 4);
            if (ok) {
                b.len = b.len + 1024 * 4;
                continue;
            }
            var b1 = try allocator.alloc(u8, b.len + 1024 * 4);
            @memcpy(b1[0..b.len], b);
            allocator.free(b);
            b = b1;
        }
    }
    if (!std.mem.endsWith(u8, b[0..l], "welovetxthinking")) {
        return error.UnexpectedResponse;
    }
    return .{ .b = b, .n = l - 16 };
}
