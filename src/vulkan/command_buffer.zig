const std = @import("std");
const c = @import("../c.zig").c;

const vk_vt = @import("vertex.zig");

pub fn record_command_buffer(
    command_buffer: c.VkCommandBuffer,
    image_index: u32,
    render_pass: c.VkRenderPass,
    swap_chain_framebuffers: []c.VkFramebuffer,
    swap_chain_extent: c.VkExtent2D,
    graphics_pipeline: c.VkPipeline,
    vertex_buffer: c.VkBuffer,
    vertices: []vk_vt.Vertex,
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

    c.vkCmdDraw(command_buffer, @intCast(vertices.len), 1, 0, 0);

    c.vkCmdEndRenderPass(command_buffer);

    if (c.vkEndCommandBuffer(command_buffer) != c.VK_SUCCESS) {
        std.log.err("Vulkan: failed to record command buffer!", .{});
        return error.Vulkan;
    }
}
