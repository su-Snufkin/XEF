// Vulkan function table for the Metal engine (libvulkan.so.1 is loaded lazily with dlopen).
#pragma once
#define VK_NO_PROTOTYPES
#define VK_USE_PLATFORM_XLIB_KHR
#include <X11/Xlib.h>
#include <vulkan/vulkan.h>
#undef None
#undef Bool
#undef Status
#undef Always

namespace xef::mtl {

#define XEF_VK_GLOBAL_FNS(X) \
    X(CreateInstance) X(EnumerateInstanceExtensionProperties) X(EnumerateInstanceVersion)

#define XEF_VK_INSTANCE_FNS(X) \
    X(DestroyInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceProperties) X(GetPhysicalDeviceProperties2) \
    X(GetPhysicalDeviceFeatures2) X(GetPhysicalDeviceQueueFamilyProperties) X(GetPhysicalDeviceMemoryProperties) \
    X(GetPhysicalDeviceFormatProperties) X(EnumerateDeviceExtensionProperties) X(CreateDevice) X(GetDeviceProcAddr) \
    X(CreateXlibSurfaceKHR) X(DestroySurfaceKHR) X(GetPhysicalDeviceSurfaceSupportKHR) \
    X(GetPhysicalDeviceSurfaceCapabilitiesKHR) X(GetPhysicalDeviceSurfaceFormatsKHR) X(GetPhysicalDeviceSurfacePresentModesKHR) \
    X(GetPhysicalDeviceImageFormatProperties)

#define XEF_VK_DEVICE_FNS(X) \
    X(DestroyDevice) X(GetDeviceQueue) X(DeviceWaitIdle) X(QueueSubmit) X(QueueWaitIdle) \
    X(AllocateMemory) X(FreeMemory) X(MapMemory) X(UnmapMemory) X(FlushMappedMemoryRanges) X(InvalidateMappedMemoryRanges) \
    X(CreateBuffer) X(DestroyBuffer) X(GetBufferMemoryRequirements) X(BindBufferMemory) X(GetBufferDeviceAddress) \
    X(CreateImage) X(DestroyImage) X(GetImageMemoryRequirements) X(BindImageMemory) X(CreateImageView) X(DestroyImageView) \
    X(CreateBufferView) X(DestroyBufferView) \
    X(CreateSampler) X(DestroySampler) X(CreateShaderModule) X(DestroyShaderModule) \
    X(CreateDescriptorSetLayout) X(DestroyDescriptorSetLayout) X(CreateDescriptorPool) X(DestroyDescriptorPool) \
    X(AllocateDescriptorSets) X(UpdateDescriptorSets) X(CreatePipelineLayout) X(DestroyPipelineLayout) \
    X(CreateGraphicsPipelines) X(CreateComputePipelines) X(DestroyPipeline) X(CreatePipelineCache) \
    X(CreateCommandPool) X(DestroyCommandPool) X(ResetCommandPool) X(AllocateCommandBuffers) X(FreeCommandBuffers) \
    X(BeginCommandBuffer) X(EndCommandBuffer) X(ResetCommandBuffer) \
    X(CreateFence) X(DestroyFence) X(ResetFences) X(WaitForFences) X(GetFenceStatus) \
    X(CreateSemaphore) X(DestroySemaphore) X(WaitSemaphores) X(SignalSemaphore) X(GetSemaphoreCounterValue) \
    X(CreateQueryPool) X(DestroyQueryPool) X(GetQueryPoolResults) \
    X(CmdBindPipeline) X(CmdBindDescriptorSets) X(CmdPushConstants) X(CmdBindVertexBuffers) X(CmdBindVertexBuffers2) \
    X(CmdBindIndexBuffer) X(CmdDraw) X(CmdDrawIndexed) X(CmdDrawIndirect) X(CmdDrawIndexedIndirect) \
    X(CmdDispatch) X(CmdDispatchIndirect) X(CmdDispatchBase) X(CmdCopyBuffer) X(CmdCopyBufferToImage) X(CmdCopyImageToBuffer) \
    X(CmdCopyImage) X(CmdBlitImage) X(CmdFillBuffer) X(CmdUpdateBuffer) X(CmdClearColorImage) X(CmdClearDepthStencilImage) \
    X(CmdPipelineBarrier) X(CmdPipelineBarrier2) X(CmdBeginRendering) X(CmdEndRendering) X(CmdResolveImage) \
    X(CmdSetViewport) X(CmdSetScissor) X(CmdSetCullMode) X(CmdSetFrontFace) X(CmdSetPrimitiveTopology) \
    X(CmdSetPrimitiveRestartEnable) X(CmdSetDepthTestEnable) X(CmdSetDepthWriteEnable) X(CmdSetDepthCompareOp) \
    X(CmdSetStencilTestEnable) X(CmdSetStencilOp) X(CmdSetStencilCompareMask) X(CmdSetStencilWriteMask) \
    X(CmdSetStencilReference) X(CmdSetDepthBias) X(CmdSetDepthBiasEnable) X(CmdSetBlendConstants) \
    X(CmdSetDepthBoundsTestEnable) X(CmdSetRasterizerDiscardEnable) X(CmdBeginQuery) X(CmdEndQuery) X(CmdResetQueryPool) \
    X(CmdCopyQueryPoolResults) X(CmdWriteTimestamp) \
    X(CreateSwapchainKHR) X(DestroySwapchainKHR) X(GetSwapchainImagesKHR) X(AcquireNextImageKHR) X(QueuePresentKHR)

#define XEF_VK_DEVICE_OPT_FNS(X) \
    X(CmdSetPolygonModeEXT) X(CmdSetDepthClampEnableEXT) X(GetMemoryHostPointerPropertiesEXT)

struct VkFns {
#define XEF_VK_DECL(n) PFN_vk##n n = nullptr;
    PFN_vkGetInstanceProcAddr GetInstanceProcAddr = nullptr;
    XEF_VK_GLOBAL_FNS(XEF_VK_DECL)
    XEF_VK_INSTANCE_FNS(XEF_VK_DECL)
    XEF_VK_DEVICE_FNS(XEF_VK_DECL)
    XEF_VK_DEVICE_OPT_FNS(XEF_VK_DECL)
#undef XEF_VK_DECL
};

extern VkFns vk;

bool vk_load_global();
bool vk_load_instance(VkInstance inst);
bool vk_load_device(VkDevice dev);

} // namespace xef::mtl
