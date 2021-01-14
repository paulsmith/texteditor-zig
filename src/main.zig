const std = @import("std");
const ascii = @import("std").ascii;
const io = @import("std").io;
const heap = @import("std").heap;
const mem = @import("std").mem;
usingnamespace @import("std").os;

pub fn main() anyerror!void {
    try enableRawMode();
    defer disableRawMode();
    try initEditor();
    defer {
        const leaked = gpa.deinit();
        if (leaked) panic("leaked memory", null);
    }
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
};

var editor = Editor{
    .orig_termios = undefined,
    .rows = undefined,
    .cols = undefined,
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
        else => .NoOp,
    };
}

inline fn ctrlKey(comptime ch: u8) u8 {
    return ch & 0x1f;
}

const stdin = io.getStdIn().reader();
const stdout = io.getStdOut().writer();

fn editorReadKey() !u8 {
    var buf: [1]u8 = undefined;
    const n = try stdin.read(buf[0..]);
    return buf[0];
}

fn editorDrawRows(writer: anytype) !void {
    var y: usize = 0;
    while (y < editor.rows) : (y += 1) {
        try writer.writeAll("~");
        if (y < editor.rows - 1) try writer.writeAll("\r\n");
    }
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

fn editorRefreshScreen(allocator: *mem.Allocator) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    var writer = buf.writer();
    try writer.writeAll("\x1b[2J");
    try writer.writeAll("\x1b[H");
    try editorDrawRows(writer);
    try writer.writeAll("\x1b[H");
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
