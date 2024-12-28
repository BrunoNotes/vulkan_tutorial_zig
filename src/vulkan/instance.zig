const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

const vk_dm = @import("debug_messenger.zig");
const enable_validation_layers = @import("vulkan.zig").enable_validation_layers;
const validation_layers = @import("vulkan.zig").validation_layers;

pub fn check_validation_layer_support(allocator: std.mem.Allocator) !bool {
    var layer_count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);

    const available_layers = try allocator.alloc(c.VkLayerProperties, layer_count);
    defer allocator.free(available_layers);
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

pub fn get_required_extensions(allocator: std.mem.Allocator) !std.ArrayListAligned([*c]const u8, null) {
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
