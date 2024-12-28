const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

const device_extensions = @import("vulkan.zig").device_extensions;

pub const QueueFamilyIndices = struct {
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

pub fn is_device_suitable(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !bool {
    var device_properties: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(device, &device_properties);

    var device_features: c.VkPhysicalDeviceFeatures = undefined;
    c.vkGetPhysicalDeviceFeatures(device, &device_features);

    var indices = try find_queue_families(allocator, device, surface);

    const extensions_supported = try check_device_extension_support(allocator, device);

    var swap_chain_adequate = false;
    var swap_chain_support = try query_swapchain_support(allocator, device, surface);
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

fn find_queue_families(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !QueueFamilyIndices {
    var indices = QueueFamilyIndices.init();

    var queue_family_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..queue_families.len) |queue_family, i| {
        var present_support: c.VkBool32 = undefined;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &present_support);

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

fn check_device_extension_support(allocator: std.mem.Allocator, device: c.VkPhysicalDevice) !bool {
    var extension_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);

    const available_extensions = try allocator.alloc(c.VkExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

    var required_extensions = std.StringHashMap(void).init(allocator);
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

fn query_swapchain_support(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !SwapChainSupportDetails {
    var details = SwapChainSupportDetails.init(allocator);
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null);

    if (format_count != 0) {
        details.formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, details.formats.ptr);
    }

    var present_mode_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &present_mode_count, null);

    if (present_mode_count != 0) {
        details.present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, details.present_modes.ptr);
    }

    return details;
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
