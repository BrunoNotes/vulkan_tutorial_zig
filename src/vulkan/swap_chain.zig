const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

pub const SwapChainSupportDetails = struct {
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

pub fn query_swapchain_support(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !SwapChainSupportDetails {
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

pub fn choose_swap_surface_format(available_formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == c.VK_FORMAT_B8G8R8A8_SRGB and available_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return available_format;
        }
    } else {
        return available_formats[0];
    }
}

pub fn choose_swap_present_mode(available_presents_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (available_presents_modes) |available_present_mode| {
        if (available_present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_present_mode;
        }
    } else {
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }
}

pub fn choose_swap_extent(capabilities: c.VkSurfaceCapabilitiesKHR, window: ?*c.GLFWwindow) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var width: i32 = 0;
        var height: i32 = 0;

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
