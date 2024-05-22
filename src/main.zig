const std = @import("std");
const builtin = @import("builtin");
const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});
const wgpu = @cImport({
    @cInclude("wgpu.h");
});

// From glfw3native.h, had some issues including that one so forwards declaring it here
extern fn glfwGetWin32Window(?*glfw.GLFWwindow) ?std.os.windows.HWND;
extern fn glfwGetCocoaWindow(?*glfw.GLFWwindow) ?*anyopaque;

// No worries about these being accessible for win builds as long as they are not referenced,
// Might change in the future though.
// https://github.com/ziglang/zig/issues/335

const objc = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

fn createMetalLayer(ns_window: *anyopaque) !*anyopaque {
    // Feels a bit like black magic, but talks to the objc runtime through.
    //
    // objc_msgSend takes a class, a selector, and a variadic list of arguments, so
    // we cast the function pointer according to our needs.
    // - https://developer.apple.com/documentation/objectivec/1456712-objc_msgsend

    // objc_msgSend(instance, selector)
    const send_fn = @as(
        *const fn (*anyopaque, objc.SEL) callconv(.C) ?*anyopaque,
        @ptrCast(&objc.objc_msgSend),
    );
    // objc_msgSend(instance, selector, bool)
    const send_bool_fn = @as(
        *const fn (*anyopaque, objc.SEL, bool) callconv(.C) void,
        @ptrCast(&objc.objc_msgSend),
    );
    // objc_msgSend(instance, selector, ptr)
    const send_ptr_fn = @as(
        *const fn (*anyopaque, objc.SEL, *anyopaque) callconv(.C) void,
        @ptrCast(&objc.objc_msgSend),
    );

    // [ns_window contentView]
    const content_view = send_fn(ns_window, objc.sel_registerName("contentView").?);
    if (content_view == null) {
        return error.GetNSViewFailed;
    }

    // [ns_window.contentView setWantsLayer:YES];
    send_bool_fn(content_view.?, objc.sel_registerName("setWantsLayer:").?, true);

    // [CAMetalLayer layer]
    const layer = send_fn(objc.objc_getClass("CAMetalLayer").?, objc.sel_registerName("layer").?);
    if (layer == null) {
        return error.GetMetalLayerFailed;
    }

    // [ns_window.contentView setLayer:layer];
    send_ptr_fn(content_view.?, objc.sel_registerName("setLayer:").?, layer.?);

    return layer.?;
}

pub fn main() !void {
    if (glfw.glfwInit() == glfw.GLFW_FALSE) {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return;
    }
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    const window = glfw.glfwCreateWindow(800, 600, "Hello, world", null, null);
    defer glfw.glfwDestroyWindow(window);
    if (window == null) {
        std.debug.print("Failed to create window\n", .{});
        return error.CreateWindowFailed;
    }

    wgpu.wgpuSetLogLevel(wgpu.WGPULogLevel_Info);
    wgpu.wgpuSetLogCallback(wgpuLogCallback, null);

    const instance = wgpu.wgpuCreateInstance(null);
    defer wgpu.wgpuInstanceRelease(instance);
    if (instance == null) {
        std.debug.print("Failed to create WGPU instance\n", .{});
        return error.CreateInstanceFailed;
    }

    const surface = switch (builtin.target.os.tag) {
        .windows => surface: {
            const surface_desc = wgpu.WGPUSurfaceDescriptorFromWindowsHWND{
                .chain = .{
                    .next = null,
                    .sType = wgpu.WGPUSType_SurfaceDescriptorFromWindowsHWND,
                },
                .hinstance = std.os.windows.kernel32.GetModuleHandleW(null).?,
                .hwnd = glfwGetWin32Window(window),
            };
            break :surface wgpu.wgpuInstanceCreateSurface(instance, &wgpu.WGPUSurfaceDescriptor{
                .nextInChain = @ptrCast(&surface_desc),
            });
        },
        .macos => surface: {
            const native_window = glfwGetCocoaWindow(window);
            if (native_window == null) {
                return error.GetCocoaWindowFailed;
            }

            const layer = try createMetalLayer(native_window.?);

            const surface_desc = wgpu.WGPUSurfaceDescriptorFromMetalLayer{
                .chain = .{
                    .next = null,
                    .sType = wgpu.WGPUSType_SurfaceDescriptorFromMetalLayer,
                },
                .layer = layer,
            };
            break :surface wgpu.wgpuInstanceCreateSurface(instance, &wgpu.WGPUSurfaceDescriptor{
                .nextInChain = @ptrCast(&surface_desc),
            });
        },
        else => unreachable,
    };
    defer wgpu.wgpuSurfaceRelease(surface);
    if (surface == null) {
        std.debug.print("Failed to create WGPU surface\n", .{});
        return error.CreateSurfaceFailed;
    }

    const adapter = adapter: {
        const options = wgpu.WGPURequestAdapterOptions{
            .powerPreference = wgpu.WGPUPowerPreference_HighPerformance,
            .compatibleSurface = surface,
        };
        var response = RequestAdapterResponse{};
        wgpu.wgpuInstanceRequestAdapter(
            instance,
            @ptrCast(&options),
            requestAdapterCallback,
            @ptrCast(&response),
        );
        if (!response.status) {
            return error.RequestAdapterFailed;
        }
        break :adapter response.adapter;
    };
    defer wgpu.wgpuAdapterRelease(adapter);
    if (adapter == null) {
        std.debug.print("Failed to get WGPU adapter\n", .{});
        return error.GetAdapterFailed;
    }

    var properties: wgpu.WGPUAdapterProperties = undefined;
    wgpu.wgpuAdapterGetProperties(adapter, &properties);
    std.debug.print("WGPU: Adapter: {s}\n", .{properties.name});
    std.debug.print("WGPU: Driver: {s}\n", .{properties.driverDescription});
    std.debug.print("WGPU: Adapter type: {}\n", .{properties.adapterType});
    std.debug.print("WGPU: Backend type: {}\n", .{properties.backendType});

    const device = device: {
        var response = RequestDeviceResponse{};

        const device_desc = wgpu.WGPUDeviceDescriptor{};
        wgpu.wgpuAdapterRequestDevice(
            adapter,
            @ptrCast(&device_desc),
            requestDeviceCallback,
            @ptrCast(&response),
        );
        if (!response.status) {
            return error.RequestDeviceFailed;
        }
        break :device response.device;
    };
    defer wgpu.wgpuDeviceRelease(device);

    wgpu.wgpuDeviceSetUncapturedErrorCallback(device, uncaputuredErrorCallback, null);
    var supported_limits = wgpu.WGPUSupportedLimits{
        .nextInChain = null,
        .limits = .{},
    };
    if (wgpu.wgpuDeviceGetLimits(device, &supported_limits) == 0) {
        std.debug.print("Failed to get WGPU limits\n", .{});
        return error.GetLimitsFailed;
    }
    std.debug.print("WGPU: Max buffer size: {}\n", .{
        supported_limits.limits.maxBufferSize,
    });

    const queue = wgpu.wgpuDeviceGetQueue(device);
    defer wgpu.wgpuQueueRelease(queue);

    var framebuffer_width: i32 = undefined;
    var framebuffer_height: i32 = undefined;
    glfw.glfwGetFramebufferSize(window, &framebuffer_width, &framebuffer_height);

    const surface_config = wgpu.WGPUSurfaceConfiguration{
        .nextInChain = null,
        .device = device,
        .format = wgpu.WGPUTextureFormat_BGRA8Unorm,
        .usage = wgpu.WGPUTextureUsage_RenderAttachment,
        .viewFormatCount = 0,
        .viewFormats = null,
        .alphaMode = wgpu.WGPUCompositeAlphaMode_Opaque,
        .width = @intCast(framebuffer_width),
        .height = @intCast(framebuffer_height),
        .presentMode = wgpu.WGPUPresentMode_Fifo,
    };
    wgpu.wgpuSurfaceConfigure(surface, &surface_config);

    const shader_desc = wgpu.WGPUShaderModuleWGSLDescriptor{
        .chain = .{
            .next = null,
            .sType = wgpu.WGPUSType_ShaderModuleWGSLDescriptor,
        },
        .code = @embedFile("triangle.wgsl"),
    };

    const shader_module = wgpu.wgpuDeviceCreateShaderModule(device, &wgpu.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&shader_desc),
        .hintCount = 0,
    });
    defer wgpu.wgpuShaderModuleRelease(shader_module);
    if (shader_module == null) {
        std.debug.print("Failed to create shader module\n", .{});
        return error.CreateShaderModuleFailed;
    }

    const pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(device, &wgpu.WGPUPipelineLayoutDescriptor{
        .bindGroupLayoutCount = 0,
        .bindGroupLayouts = null,
    });
    defer wgpu.wgpuPipelineLayoutRelease(pipeline_layout);
    if (pipeline_layout == null) {
        std.debug.print("Failed to create pipeline layout\n", .{});
        return error.CreatePipelineLayoutFailed;
    }

    const pipeline_desc = wgpu.WGPURenderPipelineDescriptor{
        .layout = pipeline_layout,
        .vertex = wgpu.WGPUVertexState{
            .module = shader_module,
            .entryPoint = "vs_main",
            .buffers = null,
        },
        .primitive = wgpu.WGPUPrimitiveState{
            .topology = wgpu.WGPUPrimitiveTopology_TriangleList,
            .stripIndexFormat = wgpu.WGPUIndexFormat_Undefined,
            .frontFace = wgpu.WGPUFrontFace_CCW,
            .cullMode = wgpu.WGPUCullMode_None,
        },
        .depthStencil = null,
        .multisample = wgpu.WGPUMultisampleState{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alphaToCoverageEnabled = 1,
        },
        .fragment = &wgpu.WGPUFragmentState{
            .module = shader_module,
            .entryPoint = "fs_main",
            .targets = &wgpu.WGPUColorTargetState{
                .format = wgpu.WGPUTextureFormat_BGRA8Unorm,
                .blend = null,
                .writeMask = wgpu.WGPUColorWriteMask_All,
            },
            .targetCount = 1,
        },
    };
    const pipeline = wgpu.wgpuDeviceCreateRenderPipeline(device, &pipeline_desc);
    defer wgpu.wgpuRenderPipelineRelease(pipeline);
    if (pipeline == null) {
        std.debug.print("Failed to create render pipeline\n", .{});
        return error.CreateRenderPipelineFailed;
    }

    while (glfw.glfwWindowShouldClose(window) == glfw.GLFW_FALSE) {
        glfw.glfwPollEvents();

        var surface_texture = wgpu.WGPUSurfaceTexture{};
        wgpu.wgpuSurfaceGetCurrentTexture(surface, &surface_texture);
        defer wgpu.wgpuTextureRelease(surface_texture.texture);

        if (surface_texture.status != wgpu.WGPUSurfaceGetCurrentTextureStatus_Success) {
            return error.SurfaceTextureInvalid;
        }

        const surface_view = wgpu.wgpuTextureCreateView(surface_texture.texture, &wgpu.WGPUTextureViewDescriptor{
            .format = wgpu.WGPUTextureFormat_BGRA8Unorm,
            .dimension = wgpu.WGPUTextureViewDimension_2D,
            .baseMipLevel = 0,
            .mipLevelCount = 1,
            .baseArrayLayer = 0,
            .arrayLayerCount = 1,
            .aspect = wgpu.WGPUTextureAspect_All,
        });
        defer wgpu.wgpuTextureViewRelease(surface_view);
        if (surface_view == null) {
            return error.SurfaceViewFailed;
        }

        const encoder = wgpu.wgpuDeviceCreateCommandEncoder(device, &.{
            .label = "encoder",
        });
        defer wgpu.wgpuCommandEncoderRelease(encoder);

        const render_pass = wgpu.wgpuCommandEncoderBeginRenderPass(encoder, &.{
            .colorAttachmentCount = 1,
            .colorAttachments = &wgpu.WGPURenderPassColorAttachment{
                .view = surface_view,
                .resolveTarget = null,
                .loadOp = wgpu.WGPULoadOp_Clear,
                .storeOp = wgpu.WGPUStoreOp_Store,
                .clearValue = .{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.0,
                    .a = 1.0,
                },
            },
            .depthStencilAttachment = null,
        });
        defer wgpu.wgpuRenderPassEncoderRelease(render_pass);

        wgpu.wgpuRenderPassEncoderSetPipeline(render_pass, pipeline);
        wgpu.wgpuRenderPassEncoderDraw(render_pass, 3, 1, 0, 0);
        wgpu.wgpuRenderPassEncoderEnd(render_pass);

        const command_buffer = wgpu.wgpuCommandEncoderFinish(encoder, &.{});
        defer wgpu.wgpuCommandBufferRelease(command_buffer);

        wgpu.wgpuQueueSubmit(queue, 1, &command_buffer);
        wgpu.wgpuSurfacePresent(surface);
    }
}

fn wgpuLogCallback(
    level: wgpu.WGPULogLevel,
    message: ?[*:0]const u8,
    _: ?*anyopaque,
) callconv(.C) void {
    std.debug.print("WGPU: {d}: {s}\n", .{
        level,
        message orelse "",
    });
}

const RequestAdapterResponse = struct {
    status: bool = false,
    adapter: wgpu.WGPUAdapter = undefined,
};
fn requestAdapterCallback(
    status: wgpu.WGPURequestAdapterStatus,
    adapter: wgpu.WGPUAdapter,
    message: ?[*:0]const u8,
    userdata: ?*anyopaque,
) callconv(.C) void {
    const response = @as(*RequestAdapterResponse, @ptrCast(@alignCast(userdata)));
    if (status != wgpu.WGPURequestAdapterStatus_Success) {
        std.debug.print("WGPU: Adapter request failed (code: {}): {s}\n", .{ status, message orelse "" });
    }
    response.* = .{ .status = true, .adapter = adapter };
}

const RequestDeviceResponse = struct {
    status: bool = false,
    device: wgpu.WGPUDevice = undefined,
};
fn requestDeviceCallback(
    status: wgpu.WGPURequestDeviceStatus,
    device: wgpu.WGPUDevice,
    message: ?[*:0]const u8,
    userdata: ?*anyopaque,
) callconv(.C) void {
    const response = @as(*RequestDeviceResponse, @ptrCast(@alignCast(userdata)));
    if (status != wgpu.WGPURequestDeviceStatus_Success) {
        std.debug.print("WGPU: Device request failed (code: {}): {s}\n", .{ status, message orelse "" });
    }
    response.* = .{ .status = true, .device = device };
}

fn uncaputuredErrorCallback(
    err: wgpu.WGPUErrorType,
    message: ?[*:0]const u8,
    _: ?*anyopaque,
) callconv(.C) void {
    std.debug.print("WGPU: Uncaptured error (code: {}): {s}\n", .{ err, message orelse "" });
}
