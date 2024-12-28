const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

const vk_dm = @import("debug_messenger.zig");
const vk_ins = @import("instance.zig");
const vk_phd = @import("physical_device.zig");
const vk_ld = @import("logical_device.zig");

pub const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
pub const enable_validation_layers = builtin.mode == .Debug;
pub const device_extensions = [_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

pub const VulkanRenderer = struct {
    instance: c.VkInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,
    present_queue: c.VkQueue,
    window: ?*c.GLFWwindow,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !VulkanRenderer {
        return std.mem.zeroInit(VulkanRenderer, .{
            .allocator = allocator,
        });
    }

    // cleanup
    pub fn deinit(self: *VulkanRenderer) void {
        if (enable_validation_layers) {
            vk_dm.destroy_debug_util_messenger_ext(self.instance, self.debug_messenger, null);
        }
        defer c.vkDestroyDevice(self.device, null);
        defer c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        defer c.vkDestroyInstance(self.instance, null);
    }

    // init_vulkan
    pub fn start(self: *VulkanRenderer, window: ?*c.GLFWwindow) !void {
        std.log.info("Init Vulkan", .{});

        self.window = window;
        try self.create_instance();
        try self.setup_debug_messenger();
        try self.create_surface();
        try self.pick_physical_device();
        try self.create_logical_device();
    }

    pub fn create_instance(self: *VulkanRenderer) !void {
        const validation_layer_support = try vk_ins.check_validation_layer_support(self.allocator);
        if (enable_validation_layers and !validation_layer_support) {
            std.log.err("Vulkan: Validation layers requested, but not available!", .{});
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

        const required_extensions = try vk_ins.get_required_extensions(self.allocator);
        defer required_extensions.deinit();

        var create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
            .enabledExtensionCount = @intCast(required_extensions.items.len),
            .ppEnabledExtensionNames = required_extensions.items.ptr,
        };

        var debug_create_info = std.mem.zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{});
        const enabled_layers: []const [*c]const u8 = &validation_layers;
        if (enable_validation_layers) {
            create_info.enabledLayerCount = @intCast(enabled_layers.len);
            create_info.ppEnabledLayerNames = enabled_layers.ptr;

            vk_dm.populate_debug_messenger_create_info(&debug_create_info);
            create_info.pNext = &debug_create_info;
        } else {
            create_info.enabledLayerCount = 0;
            create_info.pNext = null;
        }

        if (c.vkCreateInstance(&create_info, null, &self.instance) != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to create vulkan instance!", .{});
            return error.Vulkan;
        }
    }

    fn setup_debug_messenger(self: *VulkanRenderer) !void {
        // _ = self;
        if (!enable_validation_layers) {
            return;
        }

        var create_info = std.mem.zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{});
        vk_dm.populate_debug_messenger_create_info(&create_info);

        const create_debug_util = vk_dm.create_debug_util_messenger_ext(self.instance, &create_info, null, &self.debug_messenger);
        if (create_debug_util != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to set up debug messenger!", .{});
            return error.Vulkan;
        }
    }

    fn create_surface(self: *VulkanRenderer) !void {
        if (c.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface) != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to create window surface", .{});
            return error.Vulkan;
        }
    }

    fn pick_physical_device(self: *VulkanRenderer) !void {
        var device_count: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(self.instance, &device_count, null);

        if (device_count == 0) {
            std.log.err("Vulkan: Failed to find GPUs with Vulkan support!", .{});
            return error.Vulkan;
        }

        const devices = try self.allocator.alloc(c.VkPhysicalDevice, device_count);
        defer self.allocator.free(devices);
        _ = c.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

        for (devices) |device| {
            if (try vk_phd.is_device_suitable(self.allocator, device, self.surface)) {
                // self.physical_device = self.allocator.dupe(c.VkPhysicalDevice, device);
                self.physical_device = device;
                break;
            }
        }

        if (self.physical_device == null) {
            std.log.err("Vulkan: Failed to find a suitable GPU!", .{});
            return error.Vulkan;
        }
    }

    fn create_logical_device(self: *VulkanRenderer) !void {
        const indices = try vk_ld.find_queue_families(self.allocator, self.physical_device, self.surface);

        var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(self.allocator);
        defer queue_create_infos.deinit();

        var unique_queue_families = std.ArrayList(u32).init(self.allocator);
        defer unique_queue_families.deinit();

        if (indices.graphics_family) |graphics_family| {
            try unique_queue_families.append(graphics_family);
        }
        if (indices.present_family) |present_family| {
            try unique_queue_families.append(present_family);
        }

        for (try unique_queue_families.toOwnedSlice()) |queue_family| {
            var queue_create_info = c.VkDeviceQueueCreateInfo{};
            queue_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
            queue_create_info.queueFamilyIndex = queue_family;
            queue_create_info.queueCount = 1;
            var queue_priority: f32 = 1.0;
            queue_create_info.pQueuePriorities = &queue_priority;
            try queue_create_infos.append(queue_create_info);
        }

        var device_features = c.VkPhysicalDeviceFeatures{};

        var create_info = c.VkDeviceCreateInfo{};
        create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        create_info.pQueueCreateInfos = queue_create_infos.items.ptr;
        create_info.queueCreateInfoCount = @intCast(queue_create_infos.items.len);
        create_info.pEnabledFeatures = &device_features;
        const enabled_extensions: []const [*c]const u8 = &device_extensions;
        create_info.enabledExtensionCount = @intCast(enabled_extensions.len);
        create_info.ppEnabledExtensionNames = enabled_extensions.ptr;

        if (enable_validation_layers) {
            const enabled_layers: []const [*c]const u8 = &validation_layers;
            create_info.enabledLayerCount = @intCast(enabled_layers.len);
            create_info.ppEnabledLayerNames = enabled_layers.ptr;
        } else {
            create_info.enabledLayerCount = 0;
        }

        if (c.vkCreateDevice(self.physical_device, &create_info, null, &self.device) != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to create logical device!", .{});
            return error.Vulkan;
        }

        if (indices.graphics_family) |graphics_family| {
            c.vkGetDeviceQueue(self.device, graphics_family, 0, &self.graphics_queue);
        }
        if (indices.present_family) |present_family| {
            c.vkGetDeviceQueue(self.device, present_family, 0, &self.present_queue);
        }
    }
};
