const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

const QueueFamilyIndices = @import("physical_device.zig").QueueFamilyIndices;

pub fn find_queue_families(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !QueueFamilyIndices {
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
