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
        switch (try editorProcessKeyPress()) {
            .Quit => {
                try stdout.writeAll("\x1b[2J");
                try stdout.writeAll("\x1b[H");
                break;
            },
            else => {},
        }
    }
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

    const Self = *@This();

    fn moveCursor(self: Self, key: u8) KeyAction {
        switch (key) {
            'a' => self.cx -= 1,
            'd' => self.cx += 1,
            'w' => self.cy -= 1,
            's' => self.cy += 1,
            else => {},
        }
        return .NoOp;
    }
};

var editor = Editor{
    .orig_termios = undefined,
    .rows = undefined,
    .cols = undefined,
    .cx = 0,
    .cy = 0,
};

fn initEditor() !void {
    const ws = try getWindowSize();
    editor.rows = ws.rows;
    editor.cols = ws.cols;
}

const KeyAction = enum { Quit, NoOp };

fn editorProcessKeyPress() !KeyAction {
    const c = try editorReadKey();
    return switch (c) {
        ctrlKey('q') => .Quit,
        'w', 'a', 's', 'd' => (&editor).moveCursor(c),
        else => .NoOp,
    };
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

fn editorReadKey() !u8 {
    const c = try readByte();
    if (c == '\x1b') {
        const c1 = readByte() catch return '\x1b';
        if (c1 == '[') {
            const c2 = readByte() catch return '\x1b';
            switch (c2) {
                'A' => return 'w',
                'B' => return 's',
                'C' => return 'd',
                'D' => return 'a',
                else => {},
            }
        }
    }
    return c;
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
