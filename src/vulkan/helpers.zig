const std = @import("std");
const c = @import("../c.zig").c;

const enable_validation_layers = @import("vulkan.zig").enable_validation_layers;
const validation_layers = @import("vulkan.zig").validation_layers;
const device_extensions = @import("vulkan.zig").device_extensions;

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

pub const Vertex = struct {
    pos: [2]f32 = .{ 0, 0 },
    color: [3]f32 = .{ 0, 0, 0 },

    pub fn get_binding_description() !c.VkVertexInputBindingDescription {
        var binding_description = c.VkVertexInputBindingDescription{};
        binding_description.binding = 0;
        binding_description.stride = @sizeOf(Vertex);
        binding_description.inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX;

        return binding_description;
    }

    pub fn get_attribute_descriptions() ![2]c.VkVertexInputAttributeDescription {
        const attribute_descriptions = [2]c.VkVertexInputAttributeDescription{
            .{
                .binding = 0,
                .location = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "pos"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
        };

        return attribute_descriptions;
    }
};

pub fn record_command_buffer(
    command_buffer: c.VkCommandBuffer,
    image_index: u32,
    render_pass: c.VkRenderPass,
    swap_chain_framebuffers: []c.VkFramebuffer,
    swap_chain_extent: c.VkExtent2D,
    graphics_pipeline: c.VkPipeline,
    vertex_buffer: c.VkBuffer,
    index_buffer: c.VkBuffer,
    indices: []u32,
    // vertices: []Vertex,
) !void {
    var begin_info = c.VkCommandBufferBeginInfo{};
    begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.flags = 0; // Optional
    begin_info.pInheritanceInfo = null; // Optional

    if (c.vkBeginCommandBuffer(command_buffer, &begin_info) != c.VK_SUCCESS) {
        std.log.err("Vulkan: failed to begin recording command buffer!", .{});
        return error.Vulkan;
    }

    var render_pass_info = c.VkRenderPassBeginInfo{};
    render_pass_info.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    render_pass_info.renderPass = render_pass;
    render_pass_info.framebuffer = swap_chain_framebuffers[image_index];
    render_pass_info.renderArea.offset = c.VkOffset2D{ .x = 0, .y = 0 };
    render_pass_info.renderArea.extent = swap_chain_extent;

    var clear_color = c.VkClearValue{
        .color = .{
            .float32 = .{ 0.0, 0.0, 0.0, 1.0 },
        },
    };
    render_pass_info.clearValueCount = 1;
    render_pass_info.pClearValues = &clear_color;

    c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

    var viewport = c.VkViewport{};
    viewport.x = 0.0;
    viewport.y = 0.0;
    viewport.width = @floatFromInt(swap_chain_extent.width);
    viewport.height = @floatFromInt(swap_chain_extent.height);
    viewport.minDepth = 0.0;
    viewport.maxDepth = 1.0;

    c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    var scissor = c.VkRect2D{};
    scissor.offset = c.VkOffset2D{ .x = 0, .y = 0 };
    scissor.extent = swap_chain_extent;

    c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    var vertex_buffers = [1]c.VkBuffer{vertex_buffer};
    var offsets = [1]c.VkDeviceSize{0};

    c.vkCmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);

    c.vkCmdBindIndexBuffer(command_buffer, index_buffer, 0, c.VK_INDEX_TYPE_UINT32);

    // c.vkCmdDraw(command_buffer, @intCast(vertices.len), 1, 0, 0);
    c.vkCmdDrawIndexed(command_buffer, @intCast(indices.len), 1, 0, 0, 0);

    c.vkCmdEndRenderPass(command_buffer);

    if (c.vkEndCommandBuffer(command_buffer) != c.VK_SUCCESS) {
        std.log.err("Vulkan: failed to record command buffer!", .{});
        return error.Vulkan;
    }
}

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

pub fn find_queue_families(allocator: std.mem.Allocator, physical_device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !QueueFamilyIndices {
    var indices = QueueFamilyIndices.init();

    var queue_family_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);

    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..queue_families.len) |queue_family, i| {
        var present_support: c.VkBool32 = undefined;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, @intCast(i), surface, &present_support);

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

pub fn create_shader_module(device: c.VkDevice, code: []u8) !c.VkShaderModule {
    var create_info = c.VkShaderModuleCreateInfo{};
    create_info.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    create_info.codeSize = code.len;
    create_info.pCode = @alignCast(@ptrCast(code.ptr));

    var shader_module: c.VkShaderModule = undefined;

    if (c.vkCreateShaderModule(device, &create_info, null, &shader_module) != c.VK_SUCCESS) {
        std.log.err("Vulkan: failed to create shader module!", .{});
        return error.Vulkan;
    }

    return shader_module;
}

pub fn find_memory_type(
    type_filter: u32,
    properties: c.VkMemoryPropertyFlags,
    physical_device: c.VkPhysicalDevice,
) !u32 {
    var mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_properties);

    for (0..mem_properties.memoryTypeCount) |i| {
        if ((type_filter & (@as(u32, 1) << @truncate(i))) != 0 and (mem_properties.memoryTypes[i].propertyFlags & properties) == properties) {
            return @truncate(i);
        }
    }

    std.log.err("Vulkan: failed to find suitable memory type!", .{});
    return error.Vulkan;
}

pub fn create_buffer(
    size: c.VkDeviceSize,
    usage: c.VkBufferUsageFlags,
    properties: c.VkMemoryPropertyFlags,
    buffer: *c.VkBuffer,
    buffer_memory: *c.VkDeviceMemory,
    device: c.VkDevice,
    physical_device: c.VkPhysicalDevice,
) !void {
    var buffer_info = c.VkBufferCreateInfo{};
    buffer_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = size;
    buffer_info.usage = usage;
    buffer_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

    if (c.vkCreateBuffer(device, &buffer_info, null, &buffer.*) != c.VK_SUCCESS) {
        std.log.err("Vulkan: failed to create vertex buffer!", .{});
    }

    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(device, buffer.*, &mem_requirements);

    var alloc_info = c.VkMemoryAllocateInfo{};
    alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_requirements.size;
    alloc_info.memoryTypeIndex = try find_memory_type(
        mem_requirements.memoryTypeBits,
        properties,
        physical_device,
    );

    if (c.vkAllocateMemory(device, &alloc_info, null, &buffer_memory.*) != c.VK_SUCCESS) {
        std.log.err("Vulkan: failed to allocate vertex buffer memory!", .{});
        return error.Vulkan;
    }

    _ = c.vkBindBufferMemory(device, buffer.*, buffer_memory.*, 0);
}

pub fn copy_buffer(
    src_buffer: c.VkBuffer,
    dst_buffer: c.VkBuffer,
    size: c.VkDeviceSize,
    command_pool: c.VkCommandPool,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
) !void {
    var alloc_info = c.VkCommandBufferAllocateInfo{};
    alloc_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc_info.commandPool = command_pool;
    alloc_info.commandBufferCount = 1;

    var command_buffer: c.VkCommandBuffer = undefined;
    _ = c.vkAllocateCommandBuffers(device, &alloc_info, &command_buffer);

    var begin_info = c.VkCommandBufferBeginInfo{};
    begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    _ = c.vkBeginCommandBuffer(command_buffer, &begin_info);

    var copy_region = c.VkBufferCopy{};
    copy_region.srcOffset = 0; // Optional
    copy_region.dstOffset = 0; // Optional
    copy_region.size = size;

    c.vkCmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region);

    _ = c.vkEndCommandBuffer(command_buffer);

    var submit_info = c.VkSubmitInfo{};
    submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command_buffer;

    _ = c.vkQueueSubmit(graphics_queue, 1, &submit_info, @ptrCast(c.VK_NULL_HANDLE));
    _ = c.vkQueueWaitIdle(graphics_queue);

    c.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
}
