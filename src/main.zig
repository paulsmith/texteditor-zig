const io = @import("std").io;
const os = @import("std").os;

pub fn main() anyerror!void {
    try enableRawMode();
    const stdin = io.getStdIn().reader();
    var buf: [1]u8 = undefined;
    while (true) {
        const n = try stdin.read(buf[0..]);
        if (n != 1 or buf[0] == 'q') break;
    }
}

fn enableRawMode() !void {
    const fd = io.getStdIn().handle;
    var raw = try os.tcgetattr(fd);
    raw.lflag &= ~@as(os.tcflag_t, os.ECHO);
    try os.tcsetattr(fd, os.TCSA.FLUSH, raw);
}
