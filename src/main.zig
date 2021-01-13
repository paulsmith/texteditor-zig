const ascii = @import("std").ascii;
const io = @import("std").io;
const os = @import("std").os;

pub fn main() anyerror!void {
    try enableRawMode();
    const stdin = io.getStdIn().reader();
    const stdout = io.getStdOut().writer();
    var buf: [1]u8 = undefined;
    while (true) {
        const n = try stdin.read(buf[0..]);
        if (n != 1 or buf[0] == 'q') break;
        const ch = buf[0];
        if (ascii.isCntrl(ch)) {
            try stdout.print("{d}\r\n", .{ch});
        } else {
            try stdout.print("{d} ('{c}')\r\n", .{ ch, ch });
        }
    }
}

var orig_termios: os.termios = undefined;
const stdin_fd = io.getStdIn().handle;

fn enableRawMode() !void {
    orig_termios = try os.tcgetattr(stdin_fd);
    try atexit(disableRawMode);
    var raw = orig_termios;
    raw.iflag &= ~@as(os.tcflag_t, os.IXON | os.ICRNL);
    raw.oflag &= ~@as(os.tcflag_t, os.OPOST);
    raw.lflag &= ~@as(os.tcflag_t, os.ECHO | os.ICANON | os.IEXTEN | os.ISIG);
    try os.tcsetattr(stdin_fd, os.TCSA.FLUSH, raw);
}

export fn disableRawMode() void {
    os.tcsetattr(stdin_fd, os.TCSA.FLUSH, orig_termios) catch unreachable;
}

// TODO(paulsmith): delete all the following when added to zig's lib/std/os.zig

const AtExitError = error{NoMemoryAvailable} || os.UnexpectedError;

// TODO(paulsmith): delete this when added to zig's lib/std/c.zig
const _c = struct {
    pub extern fn atexit(function: ?fn () callconv(.C) void) c_int;
};

fn atexit(comptime function_ptr: anytype) AtExitError!void {
    const ti = @typeInfo(@TypeOf(function_ptr));
    if (ti.Fn.return_type.? != void or ti.Fn.args.len != 0 or ti.Fn.calling_convention != .C) {
        @compileError("atexit registered function must have return type void, take no args, and use C calling convention");
    }
    switch (os.errno(_c.atexit(function_ptr))) {
        0 => return,
        os.ENOMEM => return AtExitError.NoMemoryAvailable,
        else => |err| return os.unexpectedErrno(err),
    }
}
