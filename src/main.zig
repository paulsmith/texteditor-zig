const std = @import("std");
const ascii = @import("std").ascii;
const io = @import("std").io;
usingnamespace @import("std").os;

pub fn main() anyerror!void {
    try enableRawMode();
    defer disableRawMode();
    while (true) {
        try editorRefreshScreen();
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

const KeyAction = enum { Quit, NoOp };

fn editorProcessKeyPress() !KeyAction {
    const c = try editorReadKey();
    return switch (c) {
        ctrlKey('q') => .Quit,
        else => .NoOp,
    };
}

const stdin = io.getStdIn().reader();
const stdout = io.getStdOut().writer();

fn editorReadKey() !u8 {
    var buf: [1]u8 = undefined;
    const n = try stdin.read(buf[0..]);
    return buf[0];
}

fn editorDrawRows() !void {
    var y: usize = 0;
    while (y < 24) : (y += 1) {
        try stdout.writeAll("~\r\n");
    }
}

inline fn ctrlKey(comptime ch: u8) u8 {
    return ch & 0x1f;
}

fn editorRefreshScreen() !void {
    try stdout.writeAll("\x1b[2J");
    try stdout.writeAll("\x1b[H");
    try editorDrawRows();
    try stdout.writeAll("\x1b[H");
}

var orig_termios: termios = undefined;
const stdin_fd = io.getStdIn().handle;

fn enableRawMode() !void {
    orig_termios = try tcgetattr(stdin_fd);
    var raw = orig_termios;
    raw.iflag &= ~@as(tcflag_t, BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.oflag &= ~@as(tcflag_t, OPOST);
    raw.cflag |= CS8;
    raw.lflag &= ~@as(tcflag_t, ECHO | ICANON | IEXTEN | ISIG);
    raw.cc[VMIN] = 0;
    raw.cc[VTIME] = 1;
    try tcsetattr(stdin_fd, TCSA.FLUSH, raw);
}

export fn disableRawMode() void {
    tcsetattr(stdin_fd, TCSA.FLUSH, orig_termios) catch panic("tcsetattr", null);
}
