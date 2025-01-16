const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

const vk_dm = @import("debug_messenger.zig");
const vk_ins = @import("instance.zig");
const vk_phd = @import("physical_device.zig");
const vk_ld = @import("logical_device.zig");
const vk_sc = @import("swap_chain.zig");
const vk_sd = @import("shader.zig");
const vk_cb = @import("command_buffer.zig");
const vk_vt = @import("vertex.zig");
const util = @import("../util/file.zig");

pub const validation_layers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
pub const enable_validation_layers = builtin.mode == .Debug;
pub const device_extensions = [_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

const MAX_FRAME_IN_FLIGHT = 2;

pub const VulkanRenderer = struct {
    instance: c.VkInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,
    present_queue: c.VkQueue,
    swap_chain: c.VkSwapchainKHR,
    swap_chain_images: []c.VkImage,
    swap_chain_image_format: c.VkFormat,
    swap_chain_extent: c.VkExtent2D,
    swap_chain_image_views: []c.VkImageView,
    render_pass: c.VkRenderPass,
    pipeline_layout: c.VkPipelineLayout,
    graphics_pipeline: c.VkPipeline,
    swap_chain_framebuffers: []c.VkFramebuffer,
    command_pool: c.VkCommandPool,
    command_buffers: []c.VkCommandBuffer,
    window: ?*c.GLFWwindow,
    allocator: std.mem.Allocator,

    image_available_semaphores: []c.VkSemaphore,
    render_finished_semaphores: []c.VkSemaphore,
    in_flight_fences: []c.VkFence,

    framebuffer_resized: bool,
    current_frame: u32,

    vertex_buffer: c.VkBuffer,
    vertex_buffer_memory: c.VkDeviceMemory,

    var vertices = [3]vk_vt.Vertex{
        .{ .pos = .{ 0.0, -0.5 }, .color = .{ 1, 0, 0 } },
        .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
        .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
    };

    pub fn init(allocator: std.mem.Allocator) !VulkanRenderer {
        return std.mem.zeroInit(VulkanRenderer, .{
            .allocator = allocator,
            .current_frame = 0,
            .framebuffer_resized = false,
        });
    }

    // cleanup
    pub fn deinit(self: *VulkanRenderer) void {
        self.cleanup_swap_chain() catch @panic("Vulkan: error cleaning swap chain!");

        c.vkDestroyBuffer(self.device, self.vertex_buffer, null);
        c.vkFreeMemory(self.device, self.vertex_buffer_memory, null);

        c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
        c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);

        c.vkDestroyRenderPass(self.device, self.render_pass, null);

        for (0..MAX_FRAME_IN_FLIGHT) |i| {
            c.vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
            c.vkDestroySemaphore(self.device, self.render_finished_semaphores[i], null);
            c.vkDestroyFence(self.device, self.in_flight_fences[i], null);
        }

        c.vkDestroyCommandPool(self.device, self.command_pool, null);

        c.vkDestroyDevice(self.device, null);

        if (enable_validation_layers) {
            vk_dm.destroy_debug_util_messenger_ext(self.instance, self.debug_messenger, null);
        }

        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }

    // init_vulkan
    pub fn start(self: *VulkanRenderer, window: ?*c.GLFWwindow) !void {
        std.log.info("Init Vulkan", .{});

        self.window = window;
        try self.create_instance();
        try self.setup_debug_messenger();
        try self.create_surface();
        try self.pick_physical_device();
        try self.create_logical_device();
        try self.create_swap_chain();
        try self.create_image_views();
        try self.create_render_pass();
        try self.create_graphics_pipeline();
        try self.create_framebuffers();
        try self.create_command_pool();
        try self.create_vextex_buffer();
        try self.create_command_buffers();
        try self.create_sync_objects();
    }

    fn cleanup_swap_chain(self: *VulkanRenderer) !void {
        for (self.swap_chain_framebuffers) |framebuffer| {
            c.vkDestroyFramebuffer(self.device, framebuffer, null);
        }

        for (self.swap_chain_image_views) |image_view| {
            // self.allocator.free(self.swap_chain_framebuffers);
            c.vkDestroyImageView(self.device, image_view, null);
        }

        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
    }

    pub fn recreate_swap_chain(self: *VulkanRenderer) !void {
        var width: i32 = 0;
        var height: i32 = 0;

        c.glfwGetFramebufferSize(self.window, &width, &height);

        while (width == 0 or height == 0) {
            std.debug.print("paused\n", .{});
            c.glfwGetFramebufferSize(self.window, &width, &height);
            c.glfwWaitEvents();
        }

        _ = c.vkDeviceWaitIdle(self.device);

        try self.cleanup_swap_chain();

        try self.create_swap_chain();
        try self.create_image_views();
        try self.create_framebuffers();
    }

    pub fn create_instance(self: *VulkanRenderer) !void {
        const validation_layer_support = try vk_ins.check_validation_layer_support(self.allocator);
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

        const required_extensions = try vk_ins.get_required_extensions(self.allocator);
        defer required_extensions.deinit();

        var create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
            .enabledExtensionCount = @intCast(required_extensions.items.len),
            .ppEnabledExtensionNames = required_extensions.items.ptr,
        };

        var debug_create_info = std.mem.zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{});
        if (enable_validation_layers) {
            create_info.enabledLayerCount = @intCast(validation_layers.len);
            create_info.ppEnabledLayerNames = &validation_layers;

            vk_dm.populate_debug_messenger_create_info(&debug_create_info);
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

    fn setup_debug_messenger(self: *VulkanRenderer) !void {
        if (!enable_validation_layers) {
            return;
        }

        var create_info = std.mem.zeroInit(c.VkDebugUtilsMessengerCreateInfoEXT, .{});
        vk_dm.populate_debug_messenger_create_info(&create_info);

        const create_debug_util = vk_dm.create_debug_util_messenger_ext(self.instance, &create_info, null, &self.debug_messenger);
        if (create_debug_util != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to set up debug messenger!", .{});
            return error.Vulkan;
        }
    }

    fn create_surface(self: *VulkanRenderer) !void {
        if (c.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface) != c.VK_SUCCESS) {
            std.log.err("Vulkan: Failed to create window surface", .{});
            return error.Vulkan;
        }
    }

    fn pick_physical_device(self: *VulkanRenderer) !void {
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
            if (try vk_phd.is_device_suitable(self.allocator, device, self.surface)) {
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

    fn create_logical_device(self: *VulkanRenderer) !void {
        const indices = try vk_ld.find_queue_families(self.allocator, self.physical_device, self.surface);

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
        create_info.enabledExtensionCount = @intCast(device_extensions.len);
        create_info.ppEnabledExtensionNames = &device_extensions;

        if (enable_validation_layers) {
            create_info.enabledLayerCount = @intCast(validation_layers.len);
            create_info.ppEnabledLayerNames = &validation_layers;
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

    fn create_swap_chain(self: *VulkanRenderer) !void {
        const swap_chain_support = try vk_sc.query_swapchain_support(self.allocator, self.physical_device, self.surface);

        const surface_format = vk_sc.choose_swap_surface_format(swap_chain_support.formats);
        const present_mode = vk_sc.choose_swap_present_mode(swap_chain_support.present_modes);
        const extent = vk_sc.choose_swap_extent(swap_chain_support.capabilities, self.window);

        var image_count = swap_chain_support.capabilities.minImageCount + 1;
        if (swap_chain_support.capabilities.maxImageCount > 0 and image_count > swap_chain_support.capabilities.maxImageCount) {
            image_count = swap_chain_support.capabilities.maxImageCount;
        }

        var create_info = c.VkSwapchainCreateInfoKHR{};
        create_info.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        create_info.surface = self.surface;
        create_info.minImageCount = image_count;
        create_info.imageFormat = surface_format.format;
        create_info.imageColorSpace = surface_format.colorSpace;
        create_info.imageExtent = extent;
        create_info.imageArrayLayers = 1;
        create_info.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        const indices = try vk_phd.find_queue_families(self.allocator, self.physical_device, self.surface);

        const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };

        if (indices.graphics_family != indices.present_family) {
            create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            create_info.queueFamilyIndexCount = 2;
            create_info.pQueueFamilyIndices = &queue_family_indices;
        } else {
            create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
            create_info.queueFamilyIndexCount = 0; // optional
            create_info.pQueueFamilyIndices = null; // optional
        }

        create_info.preTransform = swap_chain_support.capabilities.currentTransform;
        create_info.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        create_info.presentMode = present_mode;
        create_info.clipped = c.VK_TRUE;
        create_info.oldSwapchain = @ptrCast(c.VK_NULL_HANDLE);

        if (c.vkCreateSwapchainKHR(self.device, &create_info, null, &self.swap_chain) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to create swap chain!", .{});
            return error.Vulkan;
        }

        if (c.vkGetSwapchainImagesKHR(self.device, self.swap_chain, &image_count, null) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to get swap chain images!", .{});
            return error.Vulkan;
        }

        self.swap_chain_images = try self.allocator.alloc(c.VkImage, image_count);

        if (c.vkGetSwapchainImagesKHR(self.device, self.swap_chain, &image_count, self.swap_chain_images.ptr) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to get swap chain images!", .{});
            return error.Vulkan;
        }

        self.swap_chain_image_format = surface_format.format;
        self.swap_chain_extent = extent;
    }

    fn create_image_views(self: *VulkanRenderer) !void {
        self.swap_chain_image_views = try self.allocator.alloc(c.VkImageView, self.swap_chain_images.len);

        for (0..self.swap_chain_images.len) |i| {
            var create_info = c.VkImageViewCreateInfo{};
            create_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
            create_info.image = self.swap_chain_images[i];
            create_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
            create_info.format = self.swap_chain_image_format;
            create_info.components.r = c.VK_COMPONENT_SWIZZLE_IDENTITY;
            create_info.components.g = c.VK_COMPONENT_SWIZZLE_IDENTITY;
            create_info.components.b = c.VK_COMPONENT_SWIZZLE_IDENTITY;
            create_info.components.a = c.VK_COMPONENT_SWIZZLE_IDENTITY;
            create_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
            create_info.subresourceRange.baseMipLevel = 0;
            create_info.subresourceRange.levelCount = 1;
            create_info.subresourceRange.baseArrayLayer = 0;
            create_info.subresourceRange.layerCount = 1;

            if (c.vkCreateImageView(self.device, &create_info, null, &self.swap_chain_image_views[i]) != c.VK_SUCCESS) {
                std.log.err("Vulkan: failed to create image views!", .{});
                return error.Vulkan;
            }
        }
    }

    fn create_render_pass(self: *VulkanRenderer) !void {
        var color_attachment = c.VkAttachmentDescription{};
        color_attachment.format = self.swap_chain_image_format;
        color_attachment.samples = c.VK_SAMPLE_COUNT_1_BIT;
        color_attachment.loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR;
        color_attachment.storeOp = c.VK_ATTACHMENT_STORE_OP_STORE;
        color_attachment.stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        color_attachment.stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE;
        color_attachment.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
        color_attachment.finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        var color_attachment_ref = c.VkAttachmentReference{};
        color_attachment_ref.attachment = 0;
        color_attachment_ref.layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        var subpass = c.VkSubpassDescription{};
        subpass.pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpass.colorAttachmentCount = 1;
        subpass.pColorAttachments = &color_attachment_ref;

        var render_pass_info = c.VkRenderPassCreateInfo{};
        render_pass_info.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        render_pass_info.attachmentCount = 1;
        render_pass_info.pAttachments = &color_attachment;
        render_pass_info.subpassCount = 1;
        render_pass_info.pSubpasses = &subpass;

        var dependency = c.VkSubpassDependency{};
        dependency.srcSubpass = c.VK_SUBPASS_EXTERNAL;
        dependency.dstSubpass = 0;
        dependency.srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependency.srcAccessMask = 0;
        dependency.dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependency.dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

        render_pass_info.dependencyCount = 1;
        render_pass_info.pDependencies = &dependency;

        if (c.vkCreateRenderPass(self.device, &render_pass_info, null, &self.render_pass) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to create render pass!", .{});
            return error.Vulkan;
        }
    }

    fn create_graphics_pipeline(self: *VulkanRenderer) !void {
        const vert_shader_code = try util.read_file(self.allocator, "shaders/compiled/triangle.vert.spv");
        const frag_shader_code = try util.read_file(self.allocator, "shaders/compiled/triangle.frag.spv");

        const vert_shader_module = try vk_sd.create_shader_module(self.device, vert_shader_code);
        const frag_shader_module = try vk_sd.create_shader_module(self.device, frag_shader_code);
        defer {
            c.vkDestroyShaderModule(self.device, vert_shader_module, null);
            c.vkDestroyShaderModule(self.device, frag_shader_module, null);
        }

        var vert_shader_stage_info = c.VkPipelineShaderStageCreateInfo{};
        vert_shader_stage_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        vert_shader_stage_info.stage = c.VK_SHADER_STAGE_VERTEX_BIT;
        vert_shader_stage_info.module = vert_shader_module;
        vert_shader_stage_info.pName = "main";

        var frag_shader_stage_info = c.VkPipelineShaderStageCreateInfo{};
        frag_shader_stage_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        frag_shader_stage_info.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
        frag_shader_stage_info.module = frag_shader_module;
        frag_shader_stage_info.pName = "main";

        const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{ vert_shader_stage_info, frag_shader_stage_info };

        const dynamic_states = [2]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };

        var dynamic_state = c.VkPipelineDynamicStateCreateInfo{};
        dynamic_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
        dynamic_state.dynamicStateCount = @intCast(dynamic_states.len);
        dynamic_state.pDynamicStates = &dynamic_states;

        var binding_description = try vk_vt.Vertex.get_binding_description();
        var attribute_descriptions = try vk_vt.Vertex.get_attribute_descriptions();

        var vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{};
        vertex_input_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vertex_input_info.vertexBindingDescriptionCount = 1;
        vertex_input_info.pVertexBindingDescriptions = &binding_description;
        vertex_input_info.vertexAttributeDescriptionCount = @intCast(attribute_descriptions.len);
        vertex_input_info.pVertexAttributeDescriptions = &attribute_descriptions;

        var input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{};
        input_assembly.sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        input_assembly.topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
        input_assembly.primitiveRestartEnable = c.VK_FALSE;

        var viewport_state = c.VkPipelineViewportStateCreateInfo{};
        viewport_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        viewport_state.viewportCount = 1;
        viewport_state.scissorCount = 1;

        var rasterizer = c.VkPipelineRasterizationStateCreateInfo{};
        rasterizer.sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rasterizer.depthClampEnable = c.VK_FALSE;
        rasterizer.rasterizerDiscardEnable = c.VK_FALSE;
        rasterizer.polygonMode = c.VK_POLYGON_MODE_FILL;
        rasterizer.lineWidth = 1.0;
        rasterizer.cullMode = c.VK_CULL_MODE_BACK_BIT;
        rasterizer.frontFace = c.VK_FRONT_FACE_CLOCKWISE;
        rasterizer.depthBiasEnable = c.VK_FALSE;
        rasterizer.depthBiasEnable = c.VK_FALSE;
        rasterizer.depthBiasConstantFactor = 0.0; // Optional
        rasterizer.depthBiasClamp = 0.0; // Optional
        rasterizer.depthBiasSlopeFactor = 0.0; // Optional

        var multisampling = c.VkPipelineMultisampleStateCreateInfo{};
        multisampling.sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        multisampling.sampleShadingEnable = c.VK_FALSE;
        multisampling.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;
        multisampling.minSampleShading = 1.0; // Optional
        multisampling.pSampleMask = null; // Optional
        multisampling.alphaToCoverageEnable = c.VK_FALSE; // Optional
        multisampling.alphaToOneEnable = c.VK_FALSE; // Optional

        var color_blend_attachment = c.VkPipelineColorBlendAttachmentState{};
        color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
        // color_blend_attachment.blendEnable = c.VK_FALSE;
        // color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE; // Optional
        // color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO; // Optional
        // color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD; // Optional
        // color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE; // Optional
        // color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO; // Optional
        // color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD; // Optional
        color_blend_attachment.blendEnable = c.VK_TRUE;
        color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
        color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD;
        color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
        color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
        color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD;

        var color_blending = c.VkPipelineColorBlendStateCreateInfo{};
        color_blending.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        // color_blending.logicOpEnable = c.VK_FALSE;
        color_blending.logicOpEnable = c.VK_TRUE;
        color_blending.logicOp = c.VK_LOGIC_OP_COPY; // Optional
        color_blending.attachmentCount = 1;
        color_blending.pAttachments = &color_blend_attachment;
        color_blending.blendConstants[0] = 0.0; // Optional
        color_blending.blendConstants[1] = 0.0; // Optional
        color_blending.blendConstants[2] = 0.0; // Optional
        color_blending.blendConstants[3] = 0.0; // Optional

        var pipeline_layout_info = c.VkPipelineLayoutCreateInfo{};
        pipeline_layout_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        pipeline_layout_info.setLayoutCount = 0; // Optional
        pipeline_layout_info.pSetLayouts = null; // Optional
        pipeline_layout_info.pushConstantRangeCount = 0; // Optional
        pipeline_layout_info.pPushConstantRanges = null; // Optional

        if (c.vkCreatePipelineLayout(self.device, &pipeline_layout_info, null, &self.pipeline_layout) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to create pipeline layout!", .{});
            return error.Vulkan;
        }

        var pipeline_info = c.VkGraphicsPipelineCreateInfo{};
        pipeline_info.sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        pipeline_info.stageCount = 2;
        pipeline_info.pStages = &shader_stages;
        pipeline_info.pVertexInputState = &vertex_input_info;
        pipeline_info.pInputAssemblyState = &input_assembly;
        pipeline_info.pViewportState = &viewport_state;
        pipeline_info.pRasterizationState = &rasterizer;
        pipeline_info.pMultisampleState = &multisampling;
        pipeline_info.pDepthStencilState = null; // Optional
        pipeline_info.pColorBlendState = &color_blending;
        pipeline_info.pDynamicState = &dynamic_state;
        pipeline_info.layout = self.pipeline_layout;
        pipeline_info.renderPass = self.render_pass;
        pipeline_info.subpass = 0;
        pipeline_info.basePipelineHandle = null; // Optional
        pipeline_info.basePipelineIndex = -1; // Optional

        if (c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_info, null, &self.graphics_pipeline) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to create graphics pipeline!", .{});
            return error.Vulkan;
        }
    }

    fn create_framebuffers(self: *VulkanRenderer) !void {
        self.swap_chain_framebuffers = try self.allocator.alloc(c.VkFramebuffer, self.swap_chain_image_views.len);

        for (0..self.swap_chain_image_views.len) |i| {
            const attachments = [1]c.VkImageView{self.swap_chain_image_views[i]};

            var framebuffer_info = c.VkFramebufferCreateInfo{};
            framebuffer_info.sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
            framebuffer_info.renderPass = self.render_pass;
            framebuffer_info.attachmentCount = 1;
            framebuffer_info.pAttachments = &attachments;
            framebuffer_info.width = self.swap_chain_extent.width;
            framebuffer_info.height = self.swap_chain_extent.height;
            framebuffer_info.layers = 1;

            if (c.vkCreateFramebuffer(self.device, &framebuffer_info, null, &self.swap_chain_framebuffers[i]) != c.VK_SUCCESS) {
                std.log.err("Vulkan: failed to create framebuffer!", .{});
                return error.Vulkan;
            }
        }
    }

    fn create_command_pool(self: *VulkanRenderer) !void {
        const queue_family_indices = try vk_ld.find_queue_families(self.allocator, self.physical_device, self.surface);

        var pool_info = c.VkCommandPoolCreateInfo{};
        pool_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        pool_info.flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        if (queue_family_indices.graphics_family) |graphics_family| {
            pool_info.queueFamilyIndex = graphics_family;
        }

        if (c.vkCreateCommandPool(self.device, &pool_info, null, &self.command_pool) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to create command pool!", .{});
            return error.Vulkan;
        }
    }

    fn create_vextex_buffer(self: *VulkanRenderer) !void {
        var buffer_info = c.VkBufferCreateInfo{};
        buffer_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        buffer_info.size = @sizeOf(@TypeOf(vertices[0])) * vertices.len;
        buffer_info.usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        buffer_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

        if (c.vkCreateBuffer(self.device, &buffer_info, null, &self.vertex_buffer) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to create vertex buffer!", .{});
        }

        var mem_requirements: c.VkMemoryRequirements = undefined;
        c.vkGetBufferMemoryRequirements(self.device, self.vertex_buffer, &mem_requirements);

        var alloc_info = c.VkMemoryAllocateInfo{};
        alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        alloc_info.allocationSize = mem_requirements.size;
        alloc_info.memoryTypeIndex = try find_memory_type(
            mem_requirements.memoryTypeBits,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            self.physical_device,
        );

        if (c.vkAllocateMemory(self.device, &alloc_info, null, &self.vertex_buffer_memory) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to allocate vertex buffer memory!", .{});
            return error.Vulkan;
        }

        _ = c.vkBindBufferMemory(self.device, self.vertex_buffer, self.vertex_buffer_memory, 0);

        var data: ?*anyopaque = undefined;
        _ = c.vkMapMemory(self.device, self.vertex_buffer_memory, 0, buffer_info.size, 0, &data);
        std.mem.copyForwards(u8, @as([*]u8, @ptrCast(data.?))[0..buffer_info.size], std.mem.sliceAsBytes(&vertices));
        c.vkUnmapMemory(self.device, self.vertex_buffer_memory);
    }

    fn create_command_buffers(self: *VulkanRenderer) !void {
        self.command_buffers = try self.allocator.alloc(c.VkCommandBuffer, MAX_FRAME_IN_FLIGHT);

        var alloc_info = c.VkCommandBufferAllocateInfo{};
        alloc_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        alloc_info.commandPool = self.command_pool;
        alloc_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        alloc_info.commandBufferCount = @intCast(self.command_buffers.len);

        if (c.vkAllocateCommandBuffers(self.device, &alloc_info, self.command_buffers.ptr) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to allocate command buffers!", .{});
            return error.Vulkan;
        }
    }

    fn create_sync_objects(self: *VulkanRenderer) !void {
        self.image_available_semaphores = try self.allocator.alloc(c.VkSemaphore, MAX_FRAME_IN_FLIGHT);
        self.render_finished_semaphores = try self.allocator.alloc(c.VkSemaphore, MAX_FRAME_IN_FLIGHT);
        self.in_flight_fences = try self.allocator.alloc(c.VkFence, MAX_FRAME_IN_FLIGHT);

        var semaphore_info = c.VkSemaphoreCreateInfo{};
        semaphore_info.sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

        var fence_info = c.VkFenceCreateInfo{};
        fence_info.sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        fence_info.flags = c.VK_FENCE_CREATE_SIGNALED_BIT;

        for (0..MAX_FRAME_IN_FLIGHT) |i| {
            if (c.vkCreateSemaphore(self.device, &semaphore_info, null, &self.image_available_semaphores[i]) != c.VK_SUCCESS or
                c.vkCreateSemaphore(self.device, &semaphore_info, null, &self.render_finished_semaphores[i]) != c.VK_SUCCESS or
                c.vkCreateFence(self.device, &fence_info, null, &self.in_flight_fences[i]) != c.VK_SUCCESS)
            {
                std.log.err("Vulkan: failed to create semaphores!", .{});
                return error.Vulkan;
            }
        }
    }

    pub fn draw_frame(self: *VulkanRenderer) !void {
        _ = c.vkWaitForFences(self.device, 1, &self.in_flight_fences[self.current_frame], c.VK_TRUE, std.math.maxInt(u64));

        var image_index: u32 = 0;

        var result = c.vkAcquireNextImageKHR(self.device, self.swap_chain, std.math.maxInt(u64), self.image_available_semaphores[self.current_frame], @ptrCast(c.VK_NULL_HANDLE), &image_index);

        if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            try self.recreate_swap_chain();
            return;
        } else if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
            std.log.err("Vulkan: failed to acquire swap chain image!", .{});
            return error.Vulkan;
        }

        _ = c.vkResetFences(self.device, 1, &self.in_flight_fences[self.current_frame]);

        _ = c.vkResetCommandBuffer(self.command_buffers[self.current_frame], 0);

        try vk_cb.record_command_buffer(
            self.command_buffers[self.current_frame],
            image_index,
            self.render_pass,
            self.swap_chain_framebuffers,
            self.swap_chain_extent,
            self.graphics_pipeline,
            self.vertex_buffer,
            &vertices,
        );

        var submit_info = c.VkSubmitInfo{};
        submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;

        var wait_semaphores = [1]c.VkSemaphore{self.image_available_semaphores[self.current_frame]};

        var wait_stages = [1]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};

        submit_info.waitSemaphoreCount = 1;
        submit_info.pWaitSemaphores = &wait_semaphores;
        submit_info.pWaitDstStageMask = &wait_stages;
        submit_info.commandBufferCount = 1;
        submit_info.pCommandBuffers = &self.command_buffers[self.current_frame];

        var signal_semaphore = [1]c.VkSemaphore{self.render_finished_semaphores[self.current_frame]};

        submit_info.signalSemaphoreCount = 1;
        submit_info.pSignalSemaphores = &signal_semaphore;

        if (c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fences[self.current_frame]) != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to submit draw command buffer!", .{});
            return error.Vulkan;
        }

        var present_info = c.VkPresentInfoKHR{};
        present_info.sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        present_info.waitSemaphoreCount = 1;
        present_info.pWaitSemaphores = &signal_semaphore;

        const swap_chains = [1]c.VkSwapchainKHR{self.swap_chain};

        present_info.swapchainCount = 1;
        present_info.pSwapchains = &swap_chains;
        present_info.pImageIndices = &image_index;
        present_info.pResults = null; // Optional

        result = c.vkQueuePresentKHR(self.present_queue, &present_info);

        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or self.framebuffer_resized) {
            self.framebuffer_resized = false;
            try self.recreate_swap_chain();
        } else if (result != c.VK_SUCCESS) {
            std.log.err("Vulkan: failed to present swap chain image!", .{});
            return error.Vulkan;
        }

        self.current_frame = (self.current_frame + 1) % MAX_FRAME_IN_FLIGHT;
    }
};

fn find_memory_type(
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
