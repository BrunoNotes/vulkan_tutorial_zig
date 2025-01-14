const std = @import("std");

const ShaderType = enum {
    vert,
    frag,
};

fn file_exists(file: [:0]const u8) bool {
    _ = std.fs.cwd().statFile(file) catch {
        return false;
    };

    return true;
}

fn build_glfw(b: *std.Build, exe: *std.Build.Step.Compile) void {
    // generate make files with cmake
    const glfw_cmake = b.addSystemCommand(&.{"cmake"});
    glfw_cmake.addArg("-S");
    glfw_cmake.addFileArg(b.path("third_party/glfw"));
    glfw_cmake.addArg("-B");
    glfw_cmake.addFileArg(b.path("third_party/glfw/build"));

    // build glfw
    const glfw_make = b.addSystemCommand(&.{"make"});
    glfw_make.addArg("-C");
    glfw_make.addFileArg(b.path("third_party/glfw/build"));

    glfw_make.step.dependOn(&glfw_cmake.step);
    exe.step.dependOn(&glfw_make.step);
}

fn compile_shaders(b: *std.Build, exe: *std.Build.Step.Compile) void {
    std.log.info("Building shaders", .{});
    const shaders_dir = b.build_root.handle.openDir("shaders", .{ .iterate = true }) catch @panic("Error opening shaders folder");
    var shaders_walker = shaders_dir.iterate();
    while (shaders_walker.next() catch @panic("Error iterating shaders folder")) |entry| {
        switch (entry.kind) {
            .file => {
                const ext = std.fs.path.extension(entry.name);
                if (std.mem.eql(u8, ext, ".glsl")) {
                    const basename = std.fs.path.basename(entry.name);
                    const name = basename[0 .. basename.len - ext.len];

                    var shader_stage: []const u8 = "";
                    var src_path_split = std.mem.splitScalar(u8, name, '.');
                    while (src_path_split.next()) |path| {
                        const s_type = std.meta.stringToEnum(ShaderType, path) orelse continue;
                        switch (s_type) {
                            .vert => {
                                shader_stage = "vertex";
                            },
                            .frag => {
                                shader_stage = "fragment";
                            },
                        }
                    }
                    const s_source = std.fmt.allocPrint(b.allocator, "shaders/{s}.glsl", .{name}) catch @panic("Error printing source shader path");
                    const s_outpath = std.fmt.allocPrint(b.allocator, "shaders/compiled/{s}.spv", .{name}) catch @panic("Error printing output shader path");
                    const s_stage_arg = std.fmt.allocPrint(b.allocator, "-fshader-stage={s}", .{shader_stage}) catch @panic("Error printing shader stage");

                    shaders_dir.makeDir("compiled") catch |err| {
                        switch (err) {
                            error.PathAlreadyExists => {},
                            else => {
                                @panic("Error creating shaders/compiled folder");
                            },
                        }
                    };

                    const s_comp = b.addSystemCommand(&.{"glslc"});
                    s_comp.addArg(s_stage_arg);
                    s_comp.addFileArg(b.path(s_source));
                    s_comp.addArg("-o");
                    s_comp.addFileArg(b.path(s_outpath));
                    // const output = s_comp.addOutputFileArg(s_outpath);
                    // std.debug.print("output: {any}\n", .{output});
                    // exe.root_module.addAnonymousImport(name, .{ .root_source_file = output });

                    exe.step.dependOn(&s_comp.step);
                }
            },
            else => {},
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vulkan_tutorial",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibCpp();

    // GLFW
    if (!file_exists("third_party/glfw/build/src/libglfw3.a")) {
        build_glfw(b, exe);
    }
    exe.addIncludePath(b.path("third_party/glfw/include"));
    exe.addObjectFile(b.path("third_party/glfw/build/src/libglfw3.a"));

    // Vulkan
    exe.linkSystemLibrary("vulkan");

    // Shaders
    compile_shaders(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
