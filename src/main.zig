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
    try enableRawMode();
    defer disableRawMode();
    try initEditor();
    while (true) {
        try editorRefreshScreen(&gpa.allocator);
        try editorProcessKeyPress();
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

    const Self = *@This();

    fn moveCursor(self: Self, arrow_key: ArrowKey) void {
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
};

var editor = Editor{
    .orig_termios = undefined,
    .rows = undefined,
    .cols = undefined,
    .cx = 0,
    .cy = 0,
    .shutting_down = false,
};

fn initEditor() !void {
    const ws = try getWindowSize();
    editor.rows = ws.rows;
    editor.cols = ws.cols;
}

fn editorProcessKeyPress() !void {
    const key = try editorReadKey();
    switch (key) {
        .char => |ch| switch (ch) {
            ctrlKey('q') => (&editor).shutting_down = true,
            else => {},
        },
        .arrow_key => |dir| (&editor).moveCursor(dir),
    }
}

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

fn editorReadKey() !Key {
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

fn editorDrawRows(writer: anytype, allocator: *mem.Allocator) !void {
    var y: usize = 0;
    while (y < editor.rows) : (y += 1) {
        if (y == editor.rows / 3) {
            var welcome = try fmt.allocPrint(allocator, "Kilo editor -- version {s}", .{kilo_version});
            defer allocator.free(welcome);
            if (welcome.len > editor.cols) welcome = welcome[0..editor.cols];
            var padding = (editor.cols - welcome.len) / 2;
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
        if (y < editor.rows - 1) try writer.writeAll("\r\n");
    }
}

fn editorRefreshScreen(allocator: *mem.Allocator) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    var writer = buf.writer();
    try writer.writeAll("\x1b[?25l");
    try writer.writeAll("\x1b[H");
    try editorDrawRows(writer, allocator);
    try writer.print("\x1b[{d};{d}H", .{ editor.cy + 1, editor.cx + 1 });
    try writer.writeAll("\x1b[?25h");
    try stdout.writeAll(buf.items);
}

const stdin_fd = io.getStdIn().handle;

fn enableRawMode() !void {
    editor.orig_termios = try tcgetattr(stdin_fd);
    var raw = editor.orig_termios;
    raw.iflag &= ~@as(tcflag_t, BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.oflag &= ~@as(tcflag_t, OPOST);
    raw.cflag |= CS8;
    raw.lflag &= ~@as(tcflag_t, ECHO | ICANON | IEXTEN | ISIG);
    raw.cc[VMIN] = 0;
    raw.cc[VTIME] = 1;
    try tcsetattr(stdin_fd, TCSA.FLUSH, raw);
}

export fn disableRawMode() void {
    tcsetattr(stdin_fd, TCSA.FLUSH, editor.orig_termios) catch panic("tcsetattr", null);
}
