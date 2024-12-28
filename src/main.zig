const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig").c;

const VulkanRenderer = @import("vulkan/vulkan.zig").VulkanRenderer;

fn GLFW_error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.log.err("GLFW: Error {d}: {s}", .{ err, description });
}

const Application = struct {
    window_width: i32,
    window_height: i32,
    window_name: [*c]const u8,
    window: ?*c.GLFWwindow,
    vk_renderer: VulkanRenderer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Application {
        return std.mem.zeroInit(Application, .{
            .vk_renderer = try VulkanRenderer.init(allocator),
            .window_width = 800,
            .window_height = 600,
            .window_name = "App",
            .allocator = allocator,
        });
    }

    // cleanup
    pub fn deinit(self: *Application) void {
        defer self.vk_renderer.deinit();
        defer c.glfwDestroyWindow(self.window);
        defer c.glfwTerminate();
    }

    pub fn run(self: *Application) !void {
        try self.init_window();
        try self.vk_renderer.start(self.window);
        try self.main_loop();
    }

    fn init_window(self: *Application) !void {
        std.log.info("Init window", .{});

        if (c.glfwInit() == c.GLFW_FALSE) {
            std.log.err("GLFW: Failed to init!", .{});
            return error.GLFWInitError;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API); // dont initialize opengl
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE); // disable resize

        _ = c.glfwSetErrorCallback(GLFW_error_callback);

        const window = c.glfwCreateWindow(self.window_width, self.window_height, self.window_name, null, null) orelse {
            std.log.err("GLFW: Error creatind window!", .{});
            return error.GLFWInitError;
        };

        self.window = window;
    }

    fn main_loop(self: *Application) !void {
        std.log.info("Main loop", .{});
        while (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) {
            c.glfwPollEvents();
        }
    }
};

pub fn main() !void {
    std.log.info("Init main", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var app = try Application.init(allocator);
    defer app.deinit();

    app.window_name = "Vulkan tutorial";

    try app.run();
}
