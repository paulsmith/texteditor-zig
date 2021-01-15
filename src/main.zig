const std = @import("std");
const ascii = @import("std").ascii;
const fmt = @import("std").fmt;
const io = @import("std").io;
const heap = @import("std").heap;
const mem = @import("std").mem;
usingnamespace @import("std").os;

const kilo_version = "0.0.1";

pub fn main() anyerror!void {
    defer {
        const leaked = gpa.deinit();
        if (leaked) panic("leaked memory", null);
    }
    var editor = try Editor.new(&gpa.allocator);
    defer gpa.allocator.destroy(editor);
    try editor.enableRawMode();
    defer editor.disableRawMode();
    while (true) {
        try editor.refreshScreen();
        try editor.processKeyPress();
        if (editor.shutting_down) break;
    }
    try stdout.writeAll("\x1b[2J");
    try stdout.writeAll("\x1b[H");
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    stdout.writeAll("\x1b[2J") catch {};
    stdout.writeAll("\x1b[H") catch {};
    std.builtin.default_panic(msg, error_return_trace);
}

var gpa = heap.GeneralPurposeAllocator(.{}){};

const Editor = struct {
    orig_termios: termios,
    rows: u16,
    cols: u16,
    cx: i16,
    cy: i16,
    shutting_down: bool,
    allocator: *mem.Allocator,

    const Self = @This();

    fn new(allocator: *mem.Allocator) !*Self {
        const ws = try getWindowSize();
        var editor = try allocator.create(Self);
        editor.* = .{
            .orig_termios = undefined,
            .rows = ws.rows,
            .cols = ws.cols,
            .cx = 0,
            .cy = 0,
            .shutting_down = false,
            .allocator = allocator,
        };
        return editor;
    }

    fn enableRawMode(self: *Self) !void {
        self.orig_termios = try tcgetattr(stdin_fd);
        var raw = self.orig_termios;
        raw.iflag &= ~@as(tcflag_t, BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        raw.oflag &= ~@as(tcflag_t, OPOST);
        raw.cflag |= CS8;
        raw.lflag &= ~@as(tcflag_t, ECHO | ICANON | IEXTEN | ISIG);
        raw.cc[VMIN] = 0;
        raw.cc[VTIME] = 1;
        try tcsetattr(stdin_fd, TCSA.FLUSH, raw);
    }

    fn disableRawMode(self: *Self) void {
        tcsetattr(stdin_fd, TCSA.FLUSH, self.orig_termios) catch panic("tcsetattr", null);
    }

    fn moveCursor(self: *Self, arrow_key: ArrowKey) void {
        switch (arrow_key) {
            .left => {
                if (self.cx > 0) self.cx -= 1;
            },
            .right => {
                if (self.cx < self.cols - 1) self.cx += 1;
            },
            .up => {
                if (self.cy > 0) self.cy -= 1;
            },
            .down => {
                if (self.cy < self.rows - 1) self.cy += 1;
            },
        }
    }

    fn processKeyPress(self: *Self) !void {
        const key = try self.readKey();
        switch (key) {
            .char => |ch| switch (ch) {
                ctrlKey('q') => self.shutting_down = true,
                else => {},
            },
            .arrow_key => |dir| self.moveCursor(dir),
        }
    }

    fn readKey(self: *Self) !Key {
        const c = try readByte();
        if (c == '\x1b') {
            const c1 = readByte() catch return Key{ .char = '\x1b' };
            if (c1 == '[') {
                const c2 = readByte() catch return Key{ .char = '\x1b' };
                switch (c2) {
                    'A' => return Key{ .arrow_key = .up },
                    'B' => return Key{ .arrow_key = .down },
                    'C' => return Key{ .arrow_key = .right },
                    'D' => return Key{ .arrow_key = .left },
                    else => {},
                }
            }
        }
        return Key{ .char = c };
    }

    fn drawRows(self: *Self, writer: anytype) !void {
        var y: usize = 0;
        while (y < self.rows) : (y += 1) {
            if (y == self.rows / 3) {
                var welcome = try fmt.allocPrint(self.allocator, "Kilo self -- version {s}", .{kilo_version});
                defer self.allocator.free(welcome);
                if (welcome.len > self.cols) welcome = welcome[0..self.cols];
                var padding = (self.cols - welcome.len) / 2;
                if (padding > 0) {
                    try writer.writeAll("~");
                    padding -= 1;
                }
                while (padding > 0) : (padding -= 1) try writer.writeAll(" ");
                try writer.writeAll(welcome);
            } else {
                try writer.writeAll("~");
            }
            try writer.writeAll("\x1b[K");
            if (y < self.rows - 1) try writer.writeAll("\r\n");
        }
    }

    fn refreshScreen(self: *Self) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        var writer = buf.writer();
        try writer.writeAll("\x1b[?25l");
        try writer.writeAll("\x1b[H");
        try self.drawRows(writer);
        try writer.print("\x1b[{d};{d}H", .{ self.cy + 1, self.cx + 1 });
        try writer.writeAll("\x1b[?25h");
        try stdout.writeAll(buf.items);
    }
};

inline fn ctrlKey(comptime ch: u8) u8 {
    return ch & 0x1f;
}

const stdin = io.getStdIn().reader();
const stdout = io.getStdOut().writer();

fn readByte() !u8 {
    var buf: [1]u8 = undefined;
    const n = try stdin.read(buf[0..]);
    return buf[0];
}

const ArrowKey = enum {
    left,
    right,
    up,
    down,
};

const Key = union(enum) {
    char: u8,
    arrow_key: ArrowKey,
};

const WindowSize = struct {
    rows: u16,
    cols: u16,
};

fn getWindowSize() !WindowSize {
    var ws: winsize = undefined;
    switch (errno(system.ioctl(stdin_fd, TIOCGWINSZ, &ws))) {
        0 => return WindowSize{ .rows = ws.ws_row, .cols = ws.ws_col },
        EBADF => return error.BadFileDescriptor,
        EINVAL => return error.InvalidRequest,
        ENOTTY => return error.NotATerminal,
        else => |err| return unexpectedErrno(err),
    }
}

const stdin_fd = io.getStdIn().handle;
