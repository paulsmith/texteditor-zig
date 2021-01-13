const io = @import("std").io;
const os = @import("std").os;
const c = @cImport(@cInclude("stdlib.h"));

pub fn main() anyerror!void {
    try enableRawMode();
    const stdin = io.getStdIn().reader();
    var buf: [1]u8 = undefined;
    while (true) {
        const n = try stdin.read(buf[0..]);
        if (n != 1 or buf[0] == 'q') break;
    }
}

var orig_termios: os.termios = undefined;
const stdin_fd = io.getStdIn().handle;

fn enableRawMode() !void {
    orig_termios = try os.tcgetattr(stdin_fd);
    if (c.atexit(disableRawMode) == -1) return error.AtExit;
    var raw = orig_termios;
    raw.lflag &= ~@as(os.tcflag_t, os.ECHO);
    try os.tcsetattr(stdin_fd, os.TCSA.FLUSH, raw);
}

export fn disableRawMode() void {
    os.tcsetattr(stdin_fd, os.TCSA.FLUSH, orig_termios) catch unreachable;
}
