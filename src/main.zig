const std = @import("std");
const helper = @import("./helper.zig");
const Server = @import("./server.zig");
const client = @import("./client.zig");

pub fn main() void {
    _main() catch |err| {
        std.debug.print("{}\n", .{err});
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
            std.debug.print("{}\n", .{error.MemoryLeak});
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
        \\    stop                              stop z daemon
        \\
        \\v20250103 https://github.com/txthinking/z
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

    if (!std.mem.eql(u8, args[1], "start")) {
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        try std.json.stringify(args[1..], .{}, string.writer());
        const r = try client.send(allocator, string.items);
        defer allocator.free(r.b);
        try stdout.print("{s}", .{r.b[0..r.n]});
        return;
    }

    if (helper.getuid() != 0) {
        return error.RootRequired;
    }

    if (std.fs.cwd().access("/etc/openwrt_release", .{})) |_| {
        const s =
            \\
            \\On OpenWrt:
            \\    - z works file
            \\    - z will not start automatically on boot, you may need to add a line to /etc/rc.local: /path/to/z start
            \\    - seeing this message generally means that z has been started
            \\    - you may also need: z e HOME $HOME
            \\    - you may also need: z e PATH $PATH
            \\
            \\
        ;
        try stdout.print(s, .{});
    } else |_| {
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
    }

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
                // const n = std.c.sysconf(std.c.OPEN_MAX);
                // for (0..@intCast(n)) |i| {
                //     _ = std.c.close(@intCast(i));
                // }
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
    std.testing.refAllDecls(@This());
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     _ = gpa.deinit();
    // }
    // const allocator = gpa.allocator();
    if (std.fs.cwd().access("/etc/openwrt_release", .{})) |_| {
        std.debug.print("hello, a.\n", .{});
    } else |_| {
        std.debug.print("hello, b.\n", .{});
    }
}
