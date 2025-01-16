const c = @import("../c.zig").c;

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
