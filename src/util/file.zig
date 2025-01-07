const std = @import("std");

pub fn read_file(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buffered = std.io.bufferedReader(file.reader());
    var buf_reader = buffered.reader();

    // i dont care for the size of the file
    const file_stat = try file.stat();
    const buffer = try buf_reader.readAllAlloc(allocator, file_stat.size);
    return buffer;
}
