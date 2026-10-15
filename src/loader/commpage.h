// XEF-OSX — macOS commpage initialization.
#pragma once
#include <stdint.h>
#include <stdbool.h>

namespace xef {

// Commpage addresses
constexpr uint64_t COMM_PAGE64_BASE_ADDRESS = 0x00007fffffe00000ull;
constexpr uint64_t COMM_PAGE64_ARM_ADDRESS  = 0x0000000fffffc000ull;
constexpr uint64_t COMM_PAGE_AREA_LENGTH    = 4096 * 2;

// Commpage field offsets (relative to commpage base)
constexpr uint32_t COMM_PAGE_SIGNATURE             = 0x000;
constexpr uint32_t COMM_PAGE_VERSION               = 0x01e;
constexpr uint32_t COMM_PAGE_CPU_CAPABILITIES64     = 0x010;
constexpr uint32_t COMM_PAGE_CPU_CAPABILITIES       = 0x020;
constexpr uint32_t COMM_PAGE_NCPUS                 = 0x022;
constexpr uint32_t COMM_PAGE_ACTIVE_CPUS           = 0x034;
constexpr uint32_t COMM_PAGE_PHYSICAL_CPUS         = 0x035;
constexpr uint32_t COMM_PAGE_LOGICAL_CPUS          = 0x036;
constexpr uint32_t COMM_PAGE_USER_PAGE_SHIFT_64    = 0x037;
constexpr uint32_t COMM_PAGE_KERNEL_PAGE_SHIFT     = 0x038;
constexpr uint32_t COMM_PAGE_MEMORY_SIZE           = 0x058;
constexpr uint32_t COMM_PAGE_TIMEBASE              = 0x060;
constexpr uint32_t COMM_PAGE_APPROX_TIME           = 0x0c0;

// CPU Capabilities flags
constexpr uint64_t kHasMMX                         = 0x00000001;
constexpr uint64_t kHasSSE                         = 0x00000002;
constexpr uint64_t kHasSSE2                        = 0x00000004;
constexpr uint64_t kHasSSE3                        = 0x00000008;
constexpr uint64_t kHasSupplementalSSE3            = 0x00000010;
constexpr uint64_t k64Bit                          = 0x00000020;
constexpr uint64_t kHasSSE4_1                      = 0x00000040;
constexpr uint64_t kHasSSE4_2                      = 0x00000080;
constexpr uint64_t kHasAES                         = 0x00000100;
constexpr uint64_t kHasAVX1_0                      = 0x00000400;
constexpr uint64_t kHasRDRAND                      = 0x00000800;
constexpr uint64_t kHasF16C                        = 0x00001000;
constexpr uint64_t kHasENFSTRG                     = 0x00002000;
constexpr uint64_t kHasFMA                         = 0x00004000;
constexpr uint64_t kHasAVX2_0                      = 0x00008000;
constexpr uint64_t kHasBMI1                        = 0x00010000;
constexpr uint64_t kHasBMI2                        = 0x00020000;
constexpr uint64_t kHasARM_AdvSIMD                 = 0x00040000;
constexpr uint64_t kHasARM_FP                      = 0x00080000;

bool commpage_init();

} // namespace xef
