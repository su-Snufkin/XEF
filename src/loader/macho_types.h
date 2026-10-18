// XEF-OSX — Mach-O and FAT binary definitions for macOS AArch64.
#pragma once
#include <stdint.h>

namespace xef {

// Magic constants
constexpr uint32_t MH_MAGIC    = 0xfeedface;
constexpr uint32_t MH_CIGAM    = 0xcefaedfe;
constexpr uint32_t MH_MAGIC_64 = 0xfeedfacf;
constexpr uint32_t MH_CIGAM_64 = 0xcffaedfe;

constexpr uint32_t FAT_MAGIC    = 0xcafebabe;
constexpr uint32_t FAT_CIGAM    = 0xbebafeca;
constexpr uint32_t FAT_MAGIC_64 = 0xcafebabf;
constexpr uint32_t FAT_CIGAM_64 = 0xbfbafeca;

// CPU Types
constexpr uint32_t CPU_ARCH_ABI64 = 0x01000000;
constexpr uint32_t CPU_TYPE_X86   = 7;
constexpr uint32_t CPU_TYPE_X86_64 = CPU_TYPE_X86 | CPU_ARCH_ABI64;
constexpr uint32_t CPU_TYPE_ARM   = 12;
constexpr uint32_t CPU_TYPE_ARM64 = CPU_TYPE_ARM | CPU_ARCH_ABI64; // 0x0100000c
constexpr uint32_t CPU_TYPE_ARM64_32 = CPU_TYPE_ARM | 0x02000000;

// CPU Subtypes
constexpr uint32_t CPU_SUBTYPE_ARM_ALL      = 0;
constexpr uint32_t CPU_SUBTYPE_ARM64_ALL    = 0;
constexpr uint32_t CPU_SUBTYPE_ARM64_V8     = 1;
constexpr uint32_t CPU_SUBTYPE_ARM64E       = 2;
constexpr uint32_t CPU_SUBTYPE_X86_64_ALL   = 3;

// Mach-O File Types
constexpr uint32_t MH_OBJECT    = 0x1;
constexpr uint32_t MH_EXECUTE   = 0x2;
constexpr uint32_t MH_FVMLIB    = 0x3;
constexpr uint32_t MH_CORE      = 0x4;
constexpr uint32_t MH_PRELOAD   = 0x5;
constexpr uint32_t MH_DYLIB     = 0x6;
constexpr uint32_t MH_DYLINKER  = 0x7;
constexpr uint32_t MH_BUNDLE    = 0x8;
constexpr uint32_t MH_DYLIB_STUB= 0x9;
constexpr uint32_t MH_DSYM      = 0xa;
constexpr uint32_t MH_KEXT_BUNDLE = 0xb;

// Mach-O Flags
constexpr uint32_t MH_NOUNDEFS                = 0x1;
constexpr uint32_t MH_INCRLINK                = 0x2;
constexpr uint32_t MH_DYLDLINK                = 0x4;
constexpr uint32_t MH_BINDATLOAD              = 0x8;
constexpr uint32_t MH_PREBOUND                = 0x10;
constexpr uint32_t MH_SPLIT_SEGS              = 0x20;
constexpr uint32_t MH_LAZY_INIT               = 0x40;
constexpr uint32_t MH_TWOLEVEL                = 0x80;
constexpr uint32_t MH_FORCE_FLAT              = 0x100;
constexpr uint32_t MH_NOMULTIDEFS             = 0x200;
constexpr uint32_t MH_NOFIXPREBINDING         = 0x400;
constexpr uint32_t MH_PREBINDABLE             = 0x800;
constexpr uint32_t MH_ALLMODSBOUND            = 0x1000;
constexpr uint32_t MH_SUBSECTIONS_VIA_SYMBOLS = 0x2000;
constexpr uint32_t MH_CANONICAL               = 0x4000;
constexpr uint32_t MH_WEAK_DEFINES            = 0x8000;
constexpr uint32_t MH_BINDS_TO_WEAK           = 0x10000;
constexpr uint32_t MH_ALLOW_STACK_EXECUTION   = 0x20000;
constexpr uint32_t MH_ROOT_SAFE               = 0x40000;
constexpr uint32_t MH_SETUID_SAFE             = 0x80000;
constexpr uint32_t MH_NO_REEXPORTED_DYLIBS    = 0x100000;
constexpr uint32_t MH_PIE                     = 0x200000;

// Load Commands
constexpr uint32_t LC_REQ_DYLD              = 0x80000000;
constexpr uint32_t LC_SEGMENT               = 0x1;
constexpr uint32_t LC_SYMTAB                = 0x2;
constexpr uint32_t LC_SYMSEG                = 0x3;
constexpr uint32_t LC_THREAD                = 0x4;
constexpr uint32_t LC_UNIXTHREAD            = 0x5;
constexpr uint32_t LC_LOADFVMLIB            = 0x6;
constexpr uint32_t LC_IDFVMLIB              = 0x7;
constexpr uint32_t LC_IDENT                 = 0x8;
constexpr uint32_t LC_FVMFILE               = 0x9;
constexpr uint32_t LC_PREBOUND_DYLIB        = 0xa;
constexpr uint32_t LC_ROUTINES              = 0xb;
constexpr uint32_t LC_SUB_FRAMEWORK         = 0xc;
constexpr uint32_t LC_SUB_UMBRELLA          = 0xd;
constexpr uint32_t LC_SUB_CLIENT            = 0xe;
constexpr uint32_t LC_SUB_LIBRARY           = 0xf;
constexpr uint32_t LC_TWOLEVEL_HINTS        = 0x10;
constexpr uint32_t LC_PREBIND_CKSUM         = 0x11;
constexpr uint32_t LC_LOAD_WEAK_DYLIB       = (0x18 | LC_REQ_DYLD);
constexpr uint32_t LC_SEGMENT_64            = 0x19;
constexpr uint32_t LC_ROUTINES_64           = 0x1a;
constexpr uint32_t LC_UUID                  = 0x1b;
constexpr uint32_t LC_RPATH                 = (0x1c | LC_REQ_DYLD);
constexpr uint32_t LC_CODE_SIGNATURE        = 0x1d;
constexpr uint32_t LC_SEGMENT_SPLIT_INFO    = 0x1e;
constexpr uint32_t LC_REEXPORT_DYLIB        = (0x1f | LC_REQ_DYLD);
constexpr uint32_t LC_LAZY_LOAD_DYLIB       = 0x20;
constexpr uint32_t LC_ENCRYPTION_INFO       = 0x21;
constexpr uint32_t LC_DYLD_INFO             = 0x22;
constexpr uint32_t LC_DYLD_INFO_ONLY        = (0x22 | LC_REQ_DYLD);
constexpr uint32_t LC_LOAD_UPWARD_DYLIB     = (0x23 | LC_REQ_DYLD);
constexpr uint32_t LC_VERSION_MIN_MACOSX    = 0x24;
constexpr uint32_t LC_VERSION_MIN_IPHONEOS  = 0x25;
constexpr uint32_t LC_FUNCTION_STARTS       = 0x26;
constexpr uint32_t LC_DYLD_ENVIRONMENT      = 0x27;
constexpr uint32_t LC_MAIN                  = (0x28 | LC_REQ_DYLD);
constexpr uint32_t LC_DATA_IN_CODE          = 0x29;
constexpr uint32_t LC_SOURCE_VERSION        = 0x2A;
constexpr uint32_t LC_DYLIB_CODE_SIGN_DRS   = 0x2B;
constexpr uint32_t LC_ENCRYPTION_INFO_64    = 0x2C;
constexpr uint32_t LC_LINKER_OPTION         = 0x2D;
constexpr uint32_t LC_LINKER_OPTIMIZATION_HINT = 0x2E;
constexpr uint32_t LC_VERSION_MIN_TVOS      = 0x2F;
constexpr uint32_t LC_VERSION_MIN_WATCHOS   = 0x30;
constexpr uint32_t LC_NOTE                  = 0x31;
constexpr uint32_t LC_BUILD_VERSION         = 0x32;
constexpr uint32_t LC_DYLD_EXPORTS_TRIE     = (0x33 | LC_REQ_DYLD);
constexpr uint32_t LC_DYLD_CHAINED_FIXUPS   = (0x34 | LC_REQ_DYLD);
constexpr uint32_t LC_FILESET_ENTRY         = (0x35 | LC_REQ_DYLD);
constexpr uint32_t LC_LOAD_DYLIB            = 0xc;
constexpr uint32_t LC_ID_DYLIB              = 0xd;
constexpr uint32_t LC_LOAD_DYLINKER         = 0xe;
constexpr uint32_t LC_ID_DYLINKER           = 0xf;

// ARM64 Thread Flavors for LC_UNIXTHREAD
constexpr uint32_t ARM_THREAD_STATE64 = 6;

// Structures
struct mach_header {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
};

struct mach_header_64 {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct load_command {
    uint32_t cmd;
    uint32_t cmdsize;
};

struct segment_command_64 {
    uint32_t cmd;
    uint32_t cmdsize;
    char     segname[16];
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    uint32_t maxprot;
    uint32_t initprot;
    uint32_t nsects;
    uint32_t flags;
};

struct section_64 {
    char     sectname[16];
    char     segname[16];
    uint64_t addr;
    uint64_t size;
    uint32_t offset;
    uint32_t align;
    uint32_t reloff;
    uint32_t nreloc;
    uint32_t flags;
    uint32_t reserved1;
    uint32_t reserved2;
    uint32_t reserved3;
};

struct lc_str {
    uint32_t offset;
};

struct dylinker_command {
    uint32_t cmd;
    uint32_t cmdsize;
    lc_str   name;
};

struct dylib {
    lc_str   name;
    uint32_t timestamp;
    uint32_t current_version;
    uint32_t compatibility_version;
};

struct dylib_command {
    uint32_t cmd;
    uint32_t cmdsize;
    dylib    dylib_info;
};

struct entry_point_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint64_t entryoff;
    uint64_t stacksize;
};

struct linkedit_data_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t dataoff;
    uint32_t datasize;
};

struct dyld_info_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t rebase_off;
    uint32_t rebase_size;
    uint32_t bind_off;
    uint32_t bind_size;
    uint32_t weak_bind_off;
    uint32_t weak_bind_size;
    uint32_t lazy_bind_off;
    uint32_t lazy_bind_size;
    uint32_t export_off;
    uint32_t export_size;
};

struct symtab_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t symoff;
    uint32_t nsyms;
    uint32_t stroff;
    uint32_t strsize;
};

struct nlist_64 {
    union {
        uint32_t n_strx;
    } n_un;
    uint8_t n_type;
    uint8_t n_sect;
    uint16_t n_desc;
    uint64_t n_value;
};

constexpr uint8_t N_STAB = 0xe0;
constexpr uint8_t N_TYPE = 0x0e;
constexpr uint8_t N_EXT  = 0x01;
constexpr uint8_t N_UNDF = 0x0;
constexpr uint8_t N_ABS  = 0x2;
constexpr uint8_t N_SECT = 0xe;

// Rebase constants
constexpr uint8_t REBASE_OPCODE_MASK                           = 0xF0;
constexpr uint8_t REBASE_IMMEDIATE_MASK                        = 0x0F;
constexpr uint8_t REBASE_OPCODE_DONE                           = 0x00;
constexpr uint8_t REBASE_OPCODE_SET_TYPE_IMM                   = 0x10;
constexpr uint8_t REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB    = 0x20;
constexpr uint8_t REBASE_OPCODE_ADD_ADDR_ULEB                  = 0x30;
constexpr uint8_t REBASE_OPCODE_ADD_ADDR_IMM_SCALED            = 0x40;
constexpr uint8_t REBASE_OPCODE_DO_REBASE_IMM_TIMES            = 0x50;
constexpr uint8_t REBASE_OPCODE_DO_REBASE_ULEB_TIMES           = 0x60;
constexpr uint8_t REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB        = 0x70;
constexpr uint8_t REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB = 0x80;

constexpr uint8_t REBASE_TYPE_POINTER                          = 1;
constexpr uint8_t REBASE_TYPE_TEXT_ABSOLUTE32                  = 2;
constexpr uint8_t REBASE_TYPE_TEXT_PCREL32                     = 3;

// Bind constants
constexpr uint8_t BIND_OPCODE_MASK                             = 0xF0;
constexpr uint8_t BIND_IMMEDIATE_MASK                          = 0x0F;
constexpr uint8_t BIND_OPCODE_DONE                             = 0x00;
constexpr uint8_t BIND_OPCODE_SET_DYLIB_ORDINAL_IMM            = 0x10;
constexpr uint8_t BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB           = 0x20;
constexpr uint8_t BIND_OPCODE_SET_DYLIB_SPECIAL_IMM            = 0x30;
constexpr uint8_t BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM    = 0x40;
constexpr uint8_t BIND_OPCODE_SET_TYPE_IMM                     = 0x50;
constexpr uint8_t BIND_OPCODE_SET_ADDEND_SLEB                  = 0x60;
constexpr uint8_t BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB      = 0x70;
constexpr uint8_t BIND_OPCODE_ADD_ADDR_ULEB                    = 0x80;
constexpr uint8_t BIND_OPCODE_DO_BIND                          = 0x90;
constexpr uint8_t BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB            = 0xA0;
constexpr uint8_t BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED      = 0xB0;
constexpr uint8_t BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB = 0xC0;

constexpr uint8_t BIND_TYPE_POINTER                            = 1;
constexpr uint8_t BIND_TYPE_TEXT_ABSOLUTE32                    = 2;
constexpr uint8_t BIND_TYPE_TEXT_PCREL32                       = 3;

struct arm_thread_state64_t {
    uint64_t x[29];
    uint64_t fp;
    uint64_t lr;
    uint64_t sp;
    uint64_t pc;
    uint32_t cpsr;
    uint32_t pad;
};

struct fat_header {
    uint32_t magic;
    uint32_t nfat_arch;
};

struct fat_arch {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t offset;
    uint32_t size;
    uint32_t align;
};

struct fat_arch_64 {
    uint32_t cputype;
    uint32_t cpusubtype;
    uint64_t offset;
    uint64_t size;
    uint32_t align;
    uint32_t reserved;
};

} // namespace xef
