const std = @import("std");
const helper = @import("./helper.zig");
const Server = @import("./server.zig");
const client = @import("./client.zig");

pub fn main() void {
    _main() catch |err| {
        helper.syslog(err);
        if (err == error.ConnectionRefused) {
            std.debug.print("z might not be running?\n", .{});
        }
        if (err == error.UnexpectedResponse) {
            const s =
                \\
                \\You may want to see detail:
                \\
                \\  $ z z
                \\
                \\very few cases require filtering zhen from syslog
                \\
            ;
            std.debug.print(s, .{});
        }
        std.process.exit(1);
        return;
    };
}

pub fn _main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) {
            helper.syslog(error.MemoryLeak);
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const stdout = std.io.getStdOut().writer();
    const help =
        \\
        \\z - process manager
        \\
        \\    start                             start z daemon and add z into system boot [root and ipv6 stack required]
        \\
        \\    <command> <arg1> <arg2> <...>     add and run command
        \\    a                                 print all commands
        \\    s <id>                            stop a command
        \\    r <id>                            restart a command
        \\    d <id>                            delete a command
        \\
        \\    e <k> <v>                         add environment variable
        \\    e                                 print all environment variables
        \\
        \\    <id>                              print stdout and stderr of command
        \\    z                                 print stdout and stderr of z
        \\
        \\
        \\v20240723 https://github.com/txthinking/z
        \\
        \\
    ;
    if (args.len == 1) {
        try stdout.print(help, .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "version") or std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v")) {
        try stdout.print(help, .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "start")) {
        if (helper.getuid() != 0) {
            return error.RootRequired;
        }
        const r = crontabL(allocator) catch null;
        defer {
            if (r) |r1| {
                allocator.free(r1.b);
            }
        }
        var cp = std.process.Child.init(&.{"crontab"}, allocator);
        cp.stdin_behavior = .Pipe;
        try cp.spawn();
        if (r) |r1| {
            var it = std.mem.splitScalar(u8, r1.b[0..r1.n], '\n');
            while (it.next()) |v| {
                if (v.len == 0 or std.mem.containsAtLeast(u8, v, 1, "z start")) {
                    continue;
                }
                errdefer _ = cp.wait() catch .Unknown;
                try cp.stdin.?.writeAll(v);
                try cp.stdin.?.writeAll("\n");
            }
        }
        {
            errdefer _ = cp.wait() catch .Unknown;
            try cp.stdin.?.writeAll("@reboot ");
            const bz = try allocator.alloc(u8, 4 * 1024);
            defer allocator.free(bz);
            const bz1 = try std.fs.selfExePath(bz);
            try cp.stdin.?.writeAll(bz1);
            try cp.stdin.?.writeAll(" start\n");
            cp.stdin.?.close();
            cp.stdin = null;
        }
        _ = try cp.wait();

        const b = try allocator.alloc(u8, 8);
        defer allocator.free(b);
        @memcpy(b, "[\"ping\"]");
        const r1 = client.send(allocator, b) catch {
            const pid1 = std.c.fork();
            if (pid1 < 0) {
                helper.syslog(error.Fork1Failed);
                std.c.exit(-1);
            }
            if (pid1 > 0) {
                std.c.exit(0);
            }
            if (pid1 == 0) {
                if (helper.setsid() == -1) {
                    helper.syslog(error.SetsidFailed);
                    std.c.exit(-1);
                }
                const pid2 = std.c.fork();
                if (pid2 < 0) {
                    helper.syslog(error.Fork2Failed);
                    std.c.exit(-1);
                }
                if (pid2 > 0) {
                    std.c.exit(0);
                }
                if (pid2 == 0) {
                    if (std.c.chdir("/") == -1) {
                        helper.syslog(error.ChdirFailed);
                        std.c.exit(-1);
                    }
                    _ = std.c.umask(0);
                    const n = helper.getdtablesize();
                    for (0..@intCast(n)) |i| {
                        _ = std.c.close(@intCast(i));
                    }
                    var s = try Server.init(allocator);
                    defer s.deinit();
                    s.start() catch |err| {
                        s.e(err);
                        return err;
                    };
                }
            }
            return;
        };
        defer allocator.free(r1.b);
        return error.MaybeZAlreadyRunning;
    }

    var l = try allocator.alloc([]u8, args.len - 1);
    var done: ?usize = null;
    defer {
        if (done) |i| {
            for (0..(i + 1)) |j| {
                allocator.free(l[j]);
            }
        }
        allocator.free(l);
    }
    for (args[1..], 0..) |v, i| {
        if (i == 0) {
            const id: ?i64 = std.fmt.parseInt(i64, v, 10) catch null;
            if (std.mem.eql(u8, v, "a") or std.mem.eql(u8, v, "s") or std.mem.eql(u8, v, "r") or std.mem.eql(u8, v, "d") or std.mem.eql(u8, v, "e") or std.mem.eql(u8, v, "z") or id != null) {
                const b = try allocator.alloc(u8, v.len);
                @memcpy(b, v);
                l[i] = b;
                done = i;
                continue;
            }
            if (std.mem.startsWith(u8, v, ".") or std.mem.containsAtLeast(u8, v, 1, "/")) {
                var ap: [std.fs.max_path_bytes]u8 = undefined;
                const b0 = try std.posix.realpath(v, &ap);
                const b = try allocator.alloc(u8, b0.len);
                @memcpy(b, b0);
                l[i] = b;
                done = i;
                continue;
            }
            // std.process.Child does not find exec on given env now, so find it first
            var s1 = std.ArrayList(u8).init(allocator);
            defer s1.deinit();
            var s2 = std.ArrayList(u8).init(allocator);
            defer s2.deinit();
            var cp = std.process.Child.init(&.{ "which", v }, allocator);
            cp.stdout_behavior = .Pipe;
            cp.stderr_behavior = .Pipe;
            try cp.spawn();
            {
                errdefer _ = cp.wait() catch .Unknown;
                try cp.collectOutput(&s1, &s2, std.fs.max_path_bytes);
            }
            _ = try cp.wait();
            if (s1.items.len == 0) {
                return error.WhichCommandNotFound;
            }
            const b = try allocator.alloc(u8, s1.items.len - 1);
            @memcpy(b, s1.items[0 .. s1.items.len - 1]);
            l[i] = b;
            done = i;
            continue;
        }
        const b = try allocator.alloc(u8, v.len);
        @memcpy(b, v);
        l[i] = b;
        done = i;
    }

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(l, .{}, string.writer());
    const r = try client.send(allocator, string.items);
    defer allocator.free(r.b);
    try stdout.print("{s}", .{r.b[0..r.n]});
}

fn crontabL(allocator: std.mem.Allocator) !?struct { b: []u8, n: usize } {
    var cp = std.process.Child.init(&.{ "crontab", "-l" }, allocator);
    cp.stdout_behavior = .Pipe;
    cp.stderr_behavior = .Pipe;
    try cp.spawn();
    var b = allocator.alloc(u8, 1024 * 4) catch |err| {
        _ = cp.wait() catch .Unknown;
        return err;
    };
    errdefer allocator.free(b);
    var l: usize = 0;
    while (true) {
        errdefer _ = cp.wait() catch .Unknown;
        const n = try cp.stdout.?.read(b[l..]);
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
    _ = try cp.wait();
    return .{ .b = b, .n = l };
}

test "simple test" {
    // std.testing.refAllDecls(@This());
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     _ = gpa.deinit();
    // }
    // const allocator = gpa.allocator();
}
