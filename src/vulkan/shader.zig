const std = @import("std");
const c = @import("../c.zig").c;

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
