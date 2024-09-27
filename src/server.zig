const std = @import("std");
const testing = std.testing;
const helper = @import("./helper.zig");

const Server = @This();

allocator: std.mem.Allocator,
z: std.fs.File,
commands: std.ArrayList(Command),
processes: std.ArrayList(Process),
envs: std.process.EnvMap,
mutex: std.Thread.Mutex,

const Command = struct {
    id: i64,
    args: [][]u8,
};

const Process = struct {
    id: i64,
    process: *std.process.Child,
};

pub fn init(allocator: std.mem.Allocator) !Server {
    try std.fs.cwd().makePath("/etc/.z");
    const f = try std.fs.cwd().createFile("/etc/.z/z", .{ .truncate = true, .exclusive = false, .mode = 0o600 });
    const l = std.ArrayList(Command).init(allocator);
    const l1 = std.ArrayList(Process).init(allocator);
    const m = std.Thread.Mutex{};
    const es = std.process.EnvMap.init(allocator);
    const s = Server{
        .allocator = allocator,
        .z = f,
        .commands = l,
        .processes = l1,
        .envs = es,
        .mutex = m,
    };
    return s;
}

pub fn deinit(self: *Server) void {
    var wait = false;
    self.mutex.lock();
    if (self.processes.items.len > 0) {
        for (self.processes.items) |v| {
            _ = v.process.kill() catch |err| {
                self.e(err);
            };
        }
        wait = true;
    }
    self.mutex.unlock();
    if (wait) {
        // wait for sub threads exit first, better communication way should probably be used
        std.time.sleep(3 * std.time.ns_per_s);
    }
    self.mutex.lock();
    for (self.commands.items) |v| {
        for (v.args) |vv| {
            self.allocator.free(vv);
        }
        self.allocator.free(v.args);
    }
    self.processes.deinit();
    self.commands.deinit();
    self.envs.deinit();
    self.z.close();
    self.mutex.unlock();
}

pub fn e(self: *Server, err: anyerror) void {
    helper.e(self.z, err);
}

pub fn start(self: *Server) !void {
    while (true) {
        if (helper.testNetwork("2001:4860:4860::8888")) |_| {
            break;
        } else |err| {
            self.e(err);
            std.time.sleep(1 * std.time.ns_per_s);
            if (helper.testNetwork("2400:3200::1")) |_| {
                break;
            } else |err1| {
                self.e(err1);
                std.time.sleep(1 * std.time.ns_per_s);
                continue;
            }
        }
    }
    const addr = try std.net.Address.parseIp6("::1", 2);
    var server = try addr.listen(.{});
    defer server.deinit();
    const r2 = try helper.readFile(self.allocator, "/etc/.z/env.json");
    if (r2) |r1| {
        defer self.allocator.free(r1.b);
        const p = try std.json.parseFromSlice([][]u8, self.allocator, r1.b[0..r1.n], .{ .allocate = .alloc_always });
        defer p.deinit();
        for (p.value) |v| {
            var it = std.mem.splitScalar(u8, v, '=');
            const k0 = it.next();
            const v0 = it.next();
            if (k0 != null and v0 != null) {
                // put will copy all the memory of parameters
                try self.envs.put(k0.?, v0.?);
            }
        }
    }
    errdefer {
        // wait for sub threads ready first, better communication way should probably be used
        std.time.sleep(3 * std.time.ns_per_s);
    }
    const r = try helper.readFile(self.allocator, "/etc/.z/command.json");
    if (r) |r1| {
        defer self.allocator.free(r1.b);
        const p = try std.json.parseFromSlice([]Command, self.allocator, r1.b[0..r1.n], .{ .allocate = .alloc_always });
        defer p.deinit();
        for (p.value) |v| {
            var args = try self.allocator.alloc([]u8, v.args.len);
            var done: ?usize = null;
            errdefer {
                if (done) |i| {
                    for (0..(i + 1)) |j| {
                        self.allocator.free(args[j]);
                    }
                }
                self.allocator.free(args);
            }
            for (v.args, 0..) |vv, i| {
                const s = try self.allocator.dupe(u8, vv);
                done = i;
                args[i] = s;
            }
            const c: Command = .{
                .id = v.id,
                .args = args,
            };
            try self.commands.append(c);
            const thread = try std.Thread.spawn(.{}, Server.run, .{ self, c });
            thread.detach();
        }
    }
    while (true) {
        const conn = try server.accept();
        const thread = try std.Thread.spawn(.{}, Server.handle, .{ self, conn });
        thread.detach();
    }
}

fn handle(self: *Server, conn: std.net.Server.Connection) void {
    self._handle(conn) catch |err| {
        self.e(err);
        return;
    };
}

fn _handle(self: *Server, conn: std.net.Server.Connection) !void {
    defer conn.stream.close();
    var b = try self.allocator.alloc(u8, 1024 * 4);
    defer self.allocator.free(b);
    var l: usize = 0;
    while (true) {
        const n = try conn.stream.read(b[l..]);
        if (n == 0) {
            break;
        }
        l += n;
        if (b[l - 1] == '\n') {
            break;
        }
        if (b.len == l) {
            const ok = self.allocator.resize(b, b.len + 1024 * 4);
            if (ok) {
                b.len = b.len + 1024 * 4;
                continue;
            }
            var b1 = try self.allocator.alloc(u8, b.len + 1024 * 4);
            @memcpy(b1[0..b.len], b);
            self.allocator.free(b);
            b = b1;
        }
    }
    if (!std.mem.endsWith(u8, b[0..l], "\n")) {
        return;
    }
    const p = try std.json.parseFromSlice([][]u8, self.allocator, b[0..(l - 1)], .{ .allocate = .alloc_always });
    defer p.deinit();
    if (p.value.len == 1 and std.mem.eql(u8, p.value[0], "ping")) {
        try self.endHandle(conn);
        return;
    }
    if (p.value.len == 1 and std.mem.eql(u8, p.value[0], "stop")) {
        try self.endHandle(conn);
        // zig 0.13.0: server.deinit will not stop accept immediately, it will set server to undefined, then will crash in next request, so exit here now.
        self.deinit();
        std.process.exit(0);
        return;
    }
    if (p.value.len == 1 and std.mem.eql(u8, p.value[0], "a")) {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.commands.items) |v| {
            var pid: std.process.Child.Id = 0;
            for (self.processes.items) |vv| {
                if (vv.id == v.id) {
                    pid = vv.process.*.id;
                    break;
                }
            }
            const ids = try std.fmt.allocPrint(self.allocator, "{}\t{}\t", .{ v.id, pid });
            defer self.allocator.free(ids);
            try conn.stream.writeAll(ids);
            const args = try std.mem.join(self.allocator, " ", v.args);
            try conn.stream.writeAll(args);
            defer self.allocator.free(args);
            try conn.stream.writeAll("\n");
        }
        try self.endHandle(conn);
        return;
    }
    if (p.value.len > 1 and std.mem.eql(u8, p.value[0], "s")) {
        for (p.value[1..]) |v0| {
            const id = try std.fmt.parseInt(i64, v0, 10);
            self.mutex.lock();
            defer self.mutex.unlock();
            for (self.processes.items) |v| {
                if (v.id == id) {
                    _ = try v.process.kill();
                }
            }
        }
        try self.endHandle(conn);
        return;
    }
    if (p.value.len > 1 and std.mem.eql(u8, p.value[0], "r")) {
        self.mutex.lock();
        for (p.value[1..]) |v0| {
            errdefer self.mutex.unlock();
            const id = try std.fmt.parseInt(i64, v0, 10);
            for (self.processes.items) |v| {
                if (v.id == id) {
                    _ = try v.process.kill();
                }
            }
        }
        self.mutex.unlock();
        std.time.sleep(3 * std.time.ns_per_s);
        self.mutex.lock();
        for (p.value[1..]) |v0| {
            errdefer self.mutex.unlock();
            const id = try std.fmt.parseInt(i64, v0, 10);
            var cmd: ?Command = null;
            for (self.commands.items) |v| {
                if (v.id == id) {
                    cmd = v;
                }
            }
            if (cmd) |cmd1| {
                const thread = try std.Thread.spawn(.{}, Server.run, .{ self, cmd1 });
                thread.detach();
            }
        }
        self.mutex.unlock();
        try self.endHandle(conn);
        return;
    }
    if (p.value.len > 1 and std.mem.eql(u8, p.value[0], "d")) {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (p.value[1..]) |v0| {
            const id = try std.fmt.parseInt(i64, v0, 10);
            for (self.processes.items) |v| {
                if (v.id == id) {
                    _ = try v.process.kill();
                }
            }
            for (self.commands.items, 0..) |v, i| {
                if (v.id == id) {
                    const cmd = self.commands.orderedRemove(i);
                    for (cmd.args) |vv| {
                        self.allocator.free(vv);
                    }
                    self.allocator.free(cmd.args);
                    break;
                }
            }
        }
        std.time.sleep(3 * std.time.ns_per_s);
        try self.saveCommands();
        try self.endHandle(conn);
        return;
    }
    if (p.value.len == 1 and std.mem.eql(u8, p.value[0], "e")) {
        self.mutex.lock();
        defer self.mutex.unlock();
        var it = self.envs.iterator();
        while (it.next()) |entry| {
            const s = try std.fmt.allocPrint(self.allocator, "{s}\t{s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            defer self.allocator.free(s);
            try conn.stream.writeAll(s);
        }
        try self.endHandle(conn);
        return;
    }
    if (p.value.len == 3 and std.mem.eql(u8, p.value[0], "e")) {
        self.mutex.lock();
        defer self.mutex.unlock();
        // put will copy all the memory of parameters
        try self.envs.put(p.value[1], p.value[2]);
        try self.saveEnvs();
        try self.endHandle(conn);
        return;
    }
    if (p.value.len == 1 and std.mem.eql(u8, p.value[0], "z")) {
        const f = try std.fs.cwd().openFile("/etc/.z/z", .{});
        defer f.close();
        const b1 = try self.allocator.alloc(u8, 1024 * 4);
        defer self.allocator.free(b1);
        while (true) {
            const n = try f.read(b1);
            if (n == 0) {
                break;
            }
            try conn.stream.writeAll(b1[0..n]);
        }
        try self.endHandle(conn);
        return;
    }
    var id0: ?i64 = null;
    if (p.value.len == 1) {
        id0 = std.fmt.parseInt(i64, p.value[0], 10) catch null;
    }
    if (id0) |v| {
        const b0 = try std.fmt.allocPrint(self.allocator, "/etc/.z/{}", .{v});
        defer self.allocator.free(b0);
        const file = try std.fs.cwd().openFile(b0, .{});
        defer file.close();
        const b1 = try self.allocator.alloc(u8, 1024 * 4);
        defer self.allocator.free(b1);
        while (true) {
            const n = try file.read(b1);
            if (n == 0) {
                break;
            }
            try conn.stream.writeAll(b1[0..n]);
        }
        try self.endHandle(conn);
        return;
    }
    var args = try self.allocator.alloc([]u8, p.value.len);
    var done: ?usize = null;
    errdefer {
        if (done) |i| {
            for (0..(i + 1)) |j| {
                self.allocator.free(args[j]);
            }
        }
        self.allocator.free(args);
    }
    for (p.value, 0..) |vv, i| {
        const s = try self.allocator.dupe(u8, vv);
        done = i;
        args[i] = s;
    }
    self.mutex.lock();
    defer self.mutex.unlock();
    var c: ?Command = null;
    outer: for (self.commands.items) |v| {
        if (v.args.len != args.len) {
            continue;
        }
        for (0..v.args.len) |i| {
            if (!std.mem.eql(u8, v.args[i], args[i])) {
                continue :outer;
            }
        }
        c = v;
        break;
    }
    if (c) |c1| {
        var got: bool = false;
        for (self.processes.items) |v| {
            if (v.id == c1.id) {
                got = true;
            }
        }
        if (!got) {
            const thread = try std.Thread.spawn(.{}, Server.run, .{ self, c1 });
            thread.detach();
        }
        try self.endHandle(conn);
        return;
    }
    var id: i64 = 1;
    if (self.commands.items.len > 0) {
        id = self.commands.items[self.commands.items.len - 1].id + 1;
    }
    const c1: Command = .{
        .id = id,
        .args = args,
    };
    try self.commands.append(c1);
    try self.saveCommands();
    const thread = try std.Thread.spawn(.{}, Server.run, .{ self, c1 });
    thread.detach();
    try self.endHandle(conn);
}

fn endHandle(self: *Server, conn: std.net.Server.Connection) !void {
    _ = self;
    try conn.stream.writeAll("welovetxthinking");
    var b: [4 * 1024]u8 = undefined;
    while (true) {
        const n = conn.stream.read(&b) catch 0;
        if (n == 0) {
            break;
        }
    }
}

fn saveCommands(self: *Server) !void {
    var string = std.ArrayList(u8).init(self.allocator);
    defer string.deinit();
    try std.json.stringify(self.commands.items, .{ .whitespace = .indent_4 }, string.writer());
    const f = try std.fs.cwd().createFile("/etc/.z/command.json", .{ .truncate = true, .exclusive = false, .mode = 0o600 });
    defer f.close();
    try f.writeAll(string.items);
    try f.sync();
}

fn saveEnvs(self: *Server) !void {
    var l = try self.allocator.alloc([]u8, self.envs.count());
    defer self.allocator.free(l);
    var done: ?usize = null;
    var index: usize = 0;
    var it = self.envs.iterator();
    defer {
        if (done) |i| {
            for (0..(i + 1)) |j| {
                self.allocator.free(l[j]);
            }
        }
    }
    while (it.next()) |entry| {
        const s = try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        l[index] = s;
        done = index;
        index = index + 1;
    }
    var string = std.ArrayList(u8).init(self.allocator);
    defer string.deinit();
    try std.json.stringify(l, .{ .whitespace = .indent_4 }, string.writer());
    const f = try std.fs.cwd().createFile("/etc/.z/env.json", .{ .truncate = true, .exclusive = false, .mode = 0o600 });
    defer f.close();
    try f.writeAll(string.items);
    try f.sync();
}

fn run(self: *Server, c: Command) void {
    self._run(c) catch |err| {
        self.e(err);
        return;
    };
}

fn _run(self: *Server, c: Command) !void {
    const b = try std.fmt.allocPrint(self.allocator, "/etc/.z/{}", .{c.id});
    defer self.allocator.free(b);
    const f = try std.fs.cwd().createFile(b, .{ .truncate = true, .exclusive = false, .mode = 0o600 });
    defer f.close();

    self.mutex.lock();
    if (self.envs.count() != 0) {
        var it = self.envs.iterator();
        while (it.next()) |entry| {
            errdefer self.mutex.unlock();
            const k = try self.allocator.dupeZ(u8, entry.key_ptr.*);
            defer self.allocator.free(k);
            const v = try self.allocator.dupeZ(u8, entry.value_ptr.*);
            defer self.allocator.free(v);
            if (helper.setenv(k, v) == -1) {
                return error.SetenvFailed;
            }
        }
    }
    self.mutex.unlock();

    var cp = std.process.Child.init(c.args, self.allocator);
    cp.stdout_behavior = .Pipe;
    cp.stderr_behavior = .Pipe;

    var envs: ?*std.process.EnvMap = null;
    defer {
        if (envs) |envs1| {
            envs1.deinit();
        }
    }
    self.mutex.lock();
    if (self.envs.count() != 0) {
        var envs0 = std.process.EnvMap.init(self.allocator);
        var it = self.envs.iterator();
        while (it.next()) |entry| {
            envs0.put(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
                self.mutex.unlock();
                return err;
            };
        }
        envs = &envs0;
        cp.env_map = &envs0;
    }
    self.mutex.unlock();

    try cp.spawn();

    self.mutex.lock();
    const p: Process = .{
        .id = c.id,
        .process = &cp,
    };
    self.processes.append(p) catch |err| {
        self.mutex.unlock();
        return err;
    };
    self.mutex.unlock();

    var m = std.Thread.Mutex{};
    const thread = std.Thread.spawn(.{}, Server.ioCopy, .{ self, f, cp.stdout.?, &m }) catch |err| {
        _ = cp.wait() catch .Unknown;
        return err;
    };
    thread.detach();
    self.ioCopy(f, cp.stderr.?, &m);

    self.mutex.lock();
    for (self.processes.items, 0..) |v, i| {
        if (v.process.*.id == p.process.*.id) {
            _ = self.processes.swapRemove(i);
            break;
        }
    }
    self.mutex.unlock();

    _ = try cp.wait();
    try f.sync();
}

fn ioCopy(self: *Server, dst: std.fs.File, src: std.fs.File, dst_mutex: *std.Thread.Mutex) void {
    var b = self.allocator.alloc(u8, 1024 * 4) catch |err| {
        self.e(err);
        return;
    };
    defer self.allocator.free(b);
    while (true) {
        const n = src.read(b) catch |err| {
            self.e(err);
            return;
        };
        if (n == 0) {
            break;
        }
        dst_mutex.lock();
        defer dst_mutex.unlock();
        dst.writeAll(b[0..n]) catch |err| {
            self.e(err);
            return;
        };
    }
}

test "server" {
    std.debug.print("hello, zhen.\n", .{});
}
