const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;
const enable_validation_layers = @import("vulkan.zig").enable_validation_layers;

pub fn populate_debug_messenger_create_info(create_info: *c.VkDebugUtilsMessengerCreateInfoEXT) void {
    create_info.sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    create_info.messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;
    create_info.messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT;
    create_info.pfnUserCallback = &debug_callback;
    create_info.pUserData = null;
}

pub fn debug_callback(
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

pub fn create_debug_util_messenger_ext(
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

pub fn destroy_debug_util_messenger_ext(
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
