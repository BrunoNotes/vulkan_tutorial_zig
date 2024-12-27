const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig").c;

const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enable_validation_layers = builtin.mode == .Debug;
const device_extensions = [_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

fn GLFW_error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.log.err("GLFW: Error {d}: {s}", .{ err, description });
}

const Application = struct {
    window_width: i32,
    window_height: i32,
    window_name: [*c]const u8,
    window: ?*c.GLFWwindow,
    instance: c.VkInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,
    present_queue: c.VkQueue,
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
        if (enable_validation_layers) {
            destroy_debug_util_messenger_ext(self.instance, self.debug_messenger, null);
        }
        defer c.vkDestroyDevice(self.device, null);
        defer c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        defer c.vkDestroyInstance(self.instance, null);
        defer c.glfwDestroyWindow(self.window);
        defer c.glfwTerminate();
    }

    pub fn run(self: *Application) !void {
        try self.init_window();
        try self.init_vulkan();
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

    fn init_vulkan(self: *Application) !void {
        std.log.info("Init Vulkan", .{});
        try self.create_instance();
        try self.setup_debug_messenger();
        try self.create_surface();
        try self.pick_physical_device();
        try self.create_logical_device();
    }

    fn create_surface(self: *Application) !void {
        if (c.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface) != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to create window surface", .{});
            return error.Vulkan;
        }
    }

    fn create_logical_device(self: *Application) !void {
        const indices = try self.find_queue_families(self.physical_device);

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

    fn pick_physical_device(self: *Application) !void {
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
            if (try self.is_device_suitable(device)) {
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

    fn is_device_suitable(self: *Application, device: c.VkPhysicalDevice) !bool {
        var device_properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &device_properties);

        var device_features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(device, &device_features);

        var indices = try self.find_queue_families(device);

        const extensions_supported = try self.check_device_extension_support(device);

        var swap_chain_adequate = false;
        var swap_chain_support = try self.query_swapchain_support(device);
        defer swap_chain_support.deinit();

        if (swap_chain_support.formats.len > 0 and swap_chain_support.present_modes.len > 0) {
            swap_chain_adequate = true;
        }

        if (device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and device_features.geometryShader == c.VK_TRUE and extensions_supported and swap_chain_adequate) {
            // only dedicated gpus are allowed
            return indices.is_complete();
        } else if (device_features.geometryShader == c.VK_TRUE and extensions_supported and swap_chain_adequate) {
            return indices.is_complete();
        } else {
            return false;
        }
    }

    fn check_device_extension_support(self: *Application, device: c.VkPhysicalDevice) !bool {
        var extension_count: u32 = 0;
        _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);

        const available_extensions = try self.allocator.alloc(c.VkExtensionProperties, extension_count);
        defer self.allocator.free(available_extensions);
        _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

        var required_extensions = std.StringHashMap(void).init(self.allocator);
        defer required_extensions.deinit();

        for (device_extensions) |extension| {
            const extension_slice: []const u8 = std.mem.span(extension);
            try required_extensions.put(extension_slice, {});
        }

        for (available_extensions) |available_extension| {
            const extension_c_str: [*c]const u8 = &available_extension.extensionName;
            _ = required_extensions.remove(std.mem.span(extension_c_str));
        }

        if (required_extensions.count() == 0) {
            return true;
        } else {
            return false;
        }
    }

    fn choose_swap_surface_format(available_formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
        for (available_formats) |available_format| {
            if (available_format.format == c.VK_FORMAT_B8G8R8A8_SRGB and available_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return available_format;
            }
        } else {
            return available_formats[0];
        }
    }

    fn choose_swap_present_mode(available_presents_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
        for (available_presents_modes) |available_present_mode| {
            if (available_present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                return available_present_mode;
            }
        } else {
            return c.VK_PRESENT_MODE_FIFO_KHR;
        }
    }

    fn choose_swap_extent(capabilities: c.VkSurfaceCapabilitiesKHR, window: *c.GLFWwindow) c.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        } else {
            var width: u32 = 0;
            var height: u32 = 0;
            c.glfwGetFramebufferSize(window, &width, &height);

            var actual_extent = c.VkExtent2D{
                .width = @intCast(width),
                .height = @intCast(height),
            };

            actual_extent.width = std.math.clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
            actual_extent.height = std.math.clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

            return actual_extent;
        }
    }

    const SwapChainSupportDetails = struct {
        capabilities: c.VkSurfaceCapabilitiesKHR,
        formats: []c.VkSurfaceFormatKHR,
        present_modes: []c.VkPresentModeKHR,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) SwapChainSupportDetails {
            return std.mem.zeroInit(SwapChainSupportDetails, .{
                .allocator = allocator,
            });
        }

        pub fn deinit(self: *SwapChainSupportDetails) void {
            defer self.allocator.free(self.formats);
            defer self.allocator.free(self.present_modes);
        }
    };

    fn query_swapchain_support(self: *Application, device: c.VkPhysicalDevice) !SwapChainSupportDetails {
        var details = SwapChainSupportDetails.init(self.allocator);
        _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, self.surface, &details.capabilities);

        var format_count: u32 = 0;
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, null);

        if (format_count != 0) {
            details.formats = try self.allocator.alloc(c.VkSurfaceFormatKHR, format_count);
            _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, details.formats.ptr);
        }

        var present_mode_count: u32 = 0;
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &present_mode_count, null);

        if (present_mode_count != 0) {
            details.present_modes = try self.allocator.alloc(c.VkPresentModeKHR, present_mode_count);
            _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, details.present_modes.ptr);
        }

        return details;
    }

    const QueueFamilyIndices = struct {
        graphics_family: ?u32,
        present_family: ?u32,

        pub fn init() QueueFamilyIndices {
            return std.mem.zeroInit(QueueFamilyIndices, .{});
        }

        pub fn is_complete(self: *QueueFamilyIndices) bool {
            if (self.graphics_family != null and self.present_family != null) {
                return true;
            } else {
                return false;
            }
        }
    };

    fn find_queue_families(self: *Application, device: c.VkPhysicalDevice) !QueueFamilyIndices {
        var indices = QueueFamilyIndices.init();

        var queue_family_count: u32 = 0;
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

        const queue_families = try self.allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer self.allocator.free(queue_families);
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        for (queue_families, 0..queue_families.len) |queue_family, i| {
            var present_support: c.VkBool32 = undefined;
            _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), self.surface, &present_support);

            if (present_support == c.VK_TRUE) {
                indices.present_family = @intCast(i);
            }
            if (queue_family.queueFlags > 0 and c.VK_QUEUE_GRAPHICS_BIT == 1) {
                indices.graphics_family = @intCast(i);
            }
            if (indices.is_complete()) {
                break;
            }
        }

        return indices;
    }

    fn create_instance(self: *Application) !void {
        std.log.info("Vulkan: create instance", .{});
        const validation_layer_support = try check_validation_layer_support(self);
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

        const required_extensions = try get_required_extensions(self.allocator);
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

            populate_debug_messenger_create_info(&debug_create_info);
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

    fn get_required_extensions(allocator: std.mem.Allocator) !std.ArrayListAligned([*c]const u8, null) {
        var glfwExtensionCount: u32 = 0;
        const glfwExtensions = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

        var required_extensions = std.ArrayList([*c]const u8).init(allocator);

        for (0..glfwExtensionCount) |i| {
            try required_extensions.append(glfwExtensions[i]);
        }

        if (enable_validation_layers) {
            try required_extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
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

    fn debug_callback(
        message_severity: c.VkDebugUtilsMessageSeverityFlagsEXT,
        message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
        p_callback_data: ?*const c.VkDebugUtilsMessengerCallbackDataEXT,
        p_user_data: ?*anyopaque,
    ) callconv(.C) c_uint {
        _ = message_type;
        _ = p_user_data;
        if (message_severity >= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
            // std.debug.print("{any}\n", .{p_callback_data});
            const msg = (p_callback_data orelse return c.VK_TRUE).pMessage orelse return c.VK_TRUE;
            std.log.warn("Vulkan, validation layer: {s} ", .{msg});
        }

        return c.VK_FALSE;
    }

    fn setup_debug_messenger(self: *Application) !void {
        // _ = self;
        if (!enable_validation_layers) {
            return;
        }

        var create_info = std.mem.zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{});
        populate_debug_messenger_create_info(&create_info);

        const create_debug_util = create_debug_util_messenger_ext(self.instance, &create_info, null, &self.debug_messenger);
        if (create_debug_util != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to set up debug messenger!", .{});
            return error.Vulkan;
        }
    }

    fn populate_debug_messenger_create_info(create_info: *c.VkDebugUtilsMessengerCreateInfoEXT) void {
        create_info.sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
        create_info.messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;
        create_info.messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT;
        create_info.pfnUserCallback = &debug_callback;
        create_info.pUserData = null;
    }

    fn create_debug_util_messenger_ext(
        instance: c.VkInstance,
        p_create_info: *c.VkDebugUtilsMessengerCreateInfoEXT,
        p_allocator: ?*c.VkAllocationCallbacks,
        p_debug_messenger: *c.VkDebugUtilsMessengerEXT,
    ) c_int {
        const get_func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(
            instance,
            "vkCreateDebugUtilsMessengerEXT",
        ));
        if (get_func) |func| {
            return func(instance, p_create_info, p_allocator, p_debug_messenger);
        } else {
            return c.VK_ERROR_EXTENSION_NOT_PRESENT;
        }
    }

    fn destroy_debug_util_messenger_ext(
        instance: c.VkInstance,
        debug_messenger: c.VkDebugUtilsMessengerEXT,
        p_allocator: ?*c.VkAllocationCallbacks,
    ) void {
        const get_func: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(
            instance,
            "vkDestroyDebugUtilsMessengerEXT",
        ));
        if (get_func) |func| {
            func(instance, debug_messenger, p_allocator);
        }
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
