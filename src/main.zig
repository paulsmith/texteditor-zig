const ascii = @import("std").ascii;
const io = @import("std").io;
const panic = @import("std").debug.panic;
usingnamespace @import("std").os;

pub fn main() anyerror!void {
    try enableRawMode();
    const stdin = io.getStdIn().reader();
    const stdout = io.getStdOut().writer();
    var buf: [1]u8 = undefined;
    while (true) {
        buf[0] = 0;
        const n = try stdin.read(buf[0..]);
        const ch = buf[0];
        if (ascii.isCntrl(ch)) {
            try stdout.print("{d}\r\n", .{ch});
        } else {
            try stdout.print("{d} ('{c}')\r\n", .{ ch, ch });
        }
        if (ch == 'q') break;
    }
}

var orig_termios: termios = undefined;
const stdin_fd = io.getStdIn().handle;

fn enableRawMode() !void {
    orig_termios = try tcgetattr(stdin_fd);
    try atexit(disableRawMode);
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
    tcsetattr(stdin_fd, TCSA.FLUSH, orig_termios) catch panic("tcsetattr", .{});
}

// TODO(paulsmith): delete all the following when added to zig's lib/std/zig

const AtExitError = error{NoMemoryAvailable} || UnexpectedError;

// TODO(paulsmith): delete this when added to zig's lib/std/c.zig
const _c = struct {
    pub extern fn atexit(function: ?fn () callconv(.C) void) c_int;
};

fn atexit(comptime function_ptr: anytype) AtExitError!void {
    const ti = @typeInfo(@TypeOf(function_ptr));
    if (ti.Fn.return_type.? != void or ti.Fn.args.len != 0 or ti.Fn.calling_convention != .C) {
        @compileError("atexit registered function must have return type void, take no args, and use C calling convention");
    }
    switch (errno(_c.atexit(function_ptr))) {
        0 => return,
        ENOMEM => return AtExitError.NoMemoryAvailable,
        else => |err| return unexpectedErrno(err),
    }
}
