const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig").c;

const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enable_validation_layers = builtin.mode == .Debug;

fn GLFW_error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.log.err("GLFW: Error {d}: {s}\n", .{ err, description });
}

const Application = struct {
    window_width: i32,
    window_height: i32,
    window_name: [*c]const u8,
    window: ?*c.GLFWwindow,
    instance: c.VkInstance,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Application {
        return std.mem.zeroInit(Application, .{
            .window_width = 800,
            .window_height = 600,
            .window_name = "App",
            .allocator = allocator,
        });
    }

    // cleanup
    pub fn deinit(self: *Application) void {
        defer c.vkDestroyInstance(self.instance, null);
        defer c.glfwDestroyWindow(self.window);
        defer c.glfwTerminate();
    }

    pub fn run(self: *Application) !void {
        try self.init_window();
        try self.init_vulkan();
        try self.main_loop();
    }

    pub fn init_window(self: *Application) !void {
        std.log.info("Init window", .{});

        if (c.glfwInit() == c.GLFW_FALSE) {
            std.log.err("GLFW: Failed to init!\n", .{});
            return error.GLFWInitError;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API); // dont initialize opengl
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE); // disable resize

        _ = c.glfwSetErrorCallback(GLFW_error_callback);

        const window = c.glfwCreateWindow(self.window_width, self.window_height, self.window_name, null, null) orelse {
            std.log.err("GLFW: Error creatind window!\n", .{});
            return error.GLFWInitError;
        };

        self.window = window;
    }

    pub fn init_vulkan(self: *Application) !void {
        std.log.info("Init Vulkan", .{});
        try self.create_instance();
    }

    pub fn create_instance(self: *Application) !void {
        std.log.info("Vulkan: create instance", .{});
        const validation_layer_support = try check_validation_layer_support(self);
        if (enable_validation_layers and !validation_layer_support) {
            std.log.err("Validation layers requested, but not available!\n", .{});
            return error.Vulkan;
        }

        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Triangle",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_3,
        };

        const required_extensions = try get_required_extensions(self.allocator);
        defer required_extensions.deinit();

        var createInfo = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
            .enabledExtensionCount = @intCast(required_extensions.items.len),
            .ppEnabledExtensionNames = required_extensions.items.ptr,
        };


        const enabled_layers: []const [*c]const u8 = &validation_layers;
        if (enable_validation_layers) {
            createInfo.enabledLayerCount = @intCast(enabled_layers.len);
            createInfo.ppEnabledLayerNames = enabled_layers.ptr;
        } else {
            createInfo.enabledLayerCount = 0;
        }

        if (c.vkCreateInstance(&createInfo, null, &self.instance) != c.VK_SUCCESS) {
            std.log.err("Failed to create vulkan instance!\n", .{});
            return error.Vulkan;
        }
    }

    fn get_required_extensions(allocator: std.mem.Allocator) !std.ArrayListAligned([*c]const u8, null) {
        var glfwExtensionCount: u32 = 0;
        const glfwExtensions = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

        var required_extensions = std.ArrayList([*c]const u8).init(allocator);

        for (0..glfwExtensionCount) |i| {
            try required_extensions.append(glfwExtensions[i]);
        }

        return required_extensions;
    }

    fn check_validation_layer_support(self: *Application) !bool {
        var layer_count: u32 = 0;
        _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);

        const available_layers = try self.allocator.alloc(c.VkLayerProperties, layer_count);
        defer self.allocator.free(available_layers);
        _ = c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

        for (validation_layers) |layer_name| {
            var layer_found = false;
            for (available_layers) |layer_properties| {
                if (std.mem.eql(u8, std.mem.sliceTo(layer_name, 0), std.mem.sliceTo(&layer_properties.layerName, 0))) {
                    layer_found = true;
                    break;
                }
            }

            return layer_found;
        }

        return true;
    }

    pub fn main_loop(self: *Application) !void {
        std.log.info("Main loop", .{});
        while (c.glfwWindowShouldClose(self.window) == 0) {
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
