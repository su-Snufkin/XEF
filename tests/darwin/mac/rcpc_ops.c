// FEAT_LRCPC / LRCPC2 loads and stores (ldapr*, ldapur*, ldapursw, stlur*): Node/V8 use them for atomic acquire loads.
#include <stdio.h>
#include <stdint.h>

static uint64_t buf[4] = {0x8182838485868788ull, 0xfedcba9876543210ull, 0x0123456789abcdefull, 0xf0f1f2f3f4f5f6f7ull};

static uint64_t t_ldapr_x(void)  { uint64_t r; __asm__ volatile(".arch armv8.3-a+rcpc\n ldapr %0, [%1]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapr_w(void)  { uint32_t r; __asm__ volatile(".arch armv8.3-a+rcpc\n ldapr %w0, [%1]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldaprh(void)   { uint32_t r; __asm__ volatile(".arch armv8.3-a+rcpc\n ldaprh %w0, [%1]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldaprb(void)   { uint32_t r; __asm__ volatile(".arch armv8.3-a+rcpc\n ldaprb %w0, [%1]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapur_x(void) { uint64_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapur %0, [%1, #-8]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapur_w(void) { uint32_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapur %w0, [%1, #4]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapurb(void)  { uint32_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapurb %w0, [%1, #7]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapursb_x(void){ uint64_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapursb %0, [%1, #7]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapursb_w(void){ uint32_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapursb %w0, [%1, #7]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapursh_x(void){ uint64_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapursh %0, [%1, #6]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapursh_w(void){ uint32_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapursh %w0, [%1, #6]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_ldapursw(void) { uint64_t r; __asm__ volatile(".arch armv8.4-a+rcpc\n ldapursw %0, [%1, #4]" : "=r"(r) : "r"((char*)buf + 8) : "memory"); return r; }
static uint64_t t_stlur(void) {
    uint64_t v = 0x1122334455667788ull;
    __asm__ volatile(".arch armv8.4-a+rcpc\n stlur %0, [%1, #8]\n stlurb %w2, [%1, #1]\n stlurh %w2, [%1, #18]" :: "r"(v), "r"((char*)buf + 8), "r"(0xaabbccddu) : "memory");
    return buf[2] ^ buf[1];
}
int main(void) {
    struct { const char* n; uint64_t (*f)(void); } T[] = {
        {"ldapr x", t_ldapr_x}, {"ldapr w", t_ldapr_w}, {"ldaprh", t_ldaprh}, {"ldaprb", t_ldaprb},
        {"ldapur x", t_ldapur_x}, {"ldapur w", t_ldapur_w}, {"ldapurb", t_ldapurb},
        {"ldapursb x", t_ldapursb_x}, {"ldapursb w", t_ldapursb_w}, {"ldapursh x", t_ldapursh_x}, {"ldapursh w", t_ldapursh_w},
        {"ldapursw", t_ldapursw}, {"stlur", t_stlur},
    };
    for (unsigned i = 0; i < sizeof T / sizeof *T; i++) printf("%-12s %016llx\n", T[i].n, (unsigned long long)T[i].f());
    return 0;
}
