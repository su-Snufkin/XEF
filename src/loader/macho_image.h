// XEF-OSX — loaded Mach-O image registry (the dyld part of the Darwin layer).
#pragma once
#include <stdint.h>
#include <string>
#include <vector>

namespace xef {

struct MachSegment {
    char name[17];
    uint64_t addr;      // slid address
    uint64_t size;      // vmsize
    uint64_t fileoff;
    uint64_t filesize;
    uint32_t initprot;
};

struct MachDep {
    std::string name;       // install name as written in the load command
    bool reexport = false;
    bool weak = false;
    struct MachImage* image = nullptr;   // nullptr: provided by the HLE (libSystem etc.)
};

struct MachImage {
    std::string path;           // guest path the image was loaded from
    std::string install_name;   // LC_ID_DYLIB (or path for the executable)
    uint64_t header = 0;        // address of the mach_header_64 (slid __TEXT)
    uint64_t slide = 0;
    uint32_t filetype = 0;
    uint32_t index = 0;         // position in the registry
    std::vector<MachSegment> segs;
    std::vector<MachDep> deps;
    std::vector<std::string> rpaths;
    const uint8_t* exports = nullptr;
    size_t exports_size = 0;
    std::vector<uint64_t> inits;        // initializer addresses, run in order
    uint64_t unwind_info = 0, unwind_info_size = 0;   // __TEXT,__unwind_info
    uint64_t eh_frame = 0, eh_frame_size = 0;         // __TEXT,__eh_frame
    uint64_t tlv_vars = 0, tlv_vars_size = 0;         // __DATA,__thread_vars
    uint64_t tlv_init = 0, tlv_init_size = 0;         // __thread_data
    uint64_t tlv_total = 0;                           // __thread_data + __thread_bss
    bool initialized = false;
    bool bound = false;
    // dyld metadata (points into the mapped __LINKEDIT)
    const uint8_t* chained = nullptr; size_t chained_size = 0;
    const uint8_t* rebase = nullptr;  size_t rebase_size = 0;
    const uint8_t* bind = nullptr;    size_t bind_size = 0;
    const uint8_t* lazy_bind = nullptr; size_t lazy_bind_size = 0;
    struct InitSection { uint64_t addr, size; uint32_t type; };
    std::vector<InitSection> init_sections;
    uint64_t entry = 0;                 // LC_MAIN / LC_UNIXTHREAD target (executables)
};

// Registry of every loaded image, in load order (the executable first).
const std::vector<MachImage*>& dyld_images();
MachImage* dyld_image_containing(uint64_t addr);

// Look up an exported symbol of `img` (follows re-exports). Returns 0 when absent.
uint64_t dyld_image_lookup(MachImage* img, const char* name);
// Flat lookup over every loaded image.
uint64_t dyld_flat_lookup(const char* name);

// Runtime dlopen(): load the dylib (and its dependencies), bind, run initializers.
MachImage* dyld_dlopen(const char* path);
// Runs the initializers of images that have not run them yet (guest thread required).
void dyld_run_initializers(uint64_t argc, uint64_t argv, uint64_t envp, uint64_t apple);

// Address of the calling thread's instance of the `__thread` variable described by `desc_addr`.
void* dyld_tlv_address(uint64_t desc_addr);

} // namespace xef
