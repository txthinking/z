const std = @import("std");
const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("syslog.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
});
const datetime = @import("datetime");

var mutex = std.Thread.Mutex{};

pub fn syslog(err: anyerror) void {
    std.c.syslog(c.LOG_ERR, "zhen: %s", @as([*c]const u8, @errorName(err)));
}

pub fn e(f: std.fs.File, err: anyerror) void {
    mutex.lock();
    defer mutex.unlock();
    datetime.DateTime.now().format("rfc3339", .{}, f.writer()) catch |err1| {
        syslog(err1);
        return;
    };
    std.fmt.format(f.writer(), " {}\n", .{err}) catch |err1| {
        syslog(err1);
        return;
    };
    f.sync() catch |err1| {
        syslog(err1);
        return;
    };
}

pub fn getuid() c_uint {
    return c.getuid();
}

pub fn setsid() c_int {
    return c.setsid();
}

pub fn getdtablesize() c_int {
    return c.getdtablesize();
}

pub fn setenv(k: [:0]const u8, v: [:0]const u8) c_int {
    return c.setenv(@as([*c]const u8, k), @as([*c]const u8, v), 1);
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) !?struct { b: []u8, n: usize } {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == std.fs.File.OpenError.FileNotFound) {
            return null;
        }
        return err;
    };
    defer file.close();
    var b = try allocator.alloc(u8, 1024 * 4);
    errdefer allocator.free(b);
    var l: usize = 0;
    while (true) {
        const n = try file.read(b[l..]);
        if (n == 0) {
            break;
        }
        l += n;
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
    return .{ .b = b, .n = l };
}

pub fn testNetwork(dns: []const u8) !void {
    const addr = try std.net.Address.parseIp6(dns, 53);
    const s = try std.posix.socket(std.posix.AF.INET6, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
    defer std.posix.close(s);
    const recv_timeout = std.posix.timeval{
        .tv_sec = 3,
        .tv_usec = 0,
    };
    try std.posix.setsockopt(s, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &std.mem.toBytes(recv_timeout));
    try std.posix.connect(s, &addr.any, addr.getOsSockLen());
    const in = .{ 0x67, 0x88, 0x1, 0x0, 0x0, 0x1, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xa, 0x74, 0x78, 0x74, 0x68, 0x69, 0x6e, 0x6b, 0x69, 0x6e, 0x67, 0x3, 0x63, 0x6f, 0x6d, 0x0, 0x0, 0x1c, 0x0, 0x1 };
    _ = try std.posix.send(s, &in, 0);
    var b: [4 * 1024]u8 = undefined;
    _ = try std.posix.recv(s, &b, 0);
}
