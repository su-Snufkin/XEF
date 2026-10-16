// FP16 vector FNEG/FABS (sign-bit operations; Apple's compiler uses FNEG .8h to build constants): 64- and 128-bit,
// NaN/Inf/-0 bit patterns kept, upper half cleared for the 64-bit form.
#include <arm_neon.h>
#include <stdio.h>
#include <string.h>
static void dump(const char *t, const void *p, int n) { const unsigned short *h = p; printf("%s", t); for (int i = 0; i < n; i++) printf(" %04x", h[i]); printf("\n"); }
int main(int argc, char **argv) {
  (void)argv;
  unsigned short in[8] = {0x3c00, 0xbc00, 0x7c00, 0xfc00, 0x7e01, 0x8000, 0x0001, 0x7bff};
  in[7] ^= (unsigned short)(argc > 99);   // not a compile-time constant
  float16x8_t v; memcpy(&v, in, 16);
  float16x8_t n = vnegq_f16(v), a = vabsq_f16(v);
  dump("neg8", &n, 8); dump("abs8", &a, 8);
  float16x4_t l; memcpy(&l, in, 8);
  float16x4_t n4 = vneg_f16(l), a4 = vabs_f16(l);
  dump("neg4", &n4, 4); dump("abs4", &a4, 4);
  uint16x8_t c = vreinterpretq_u16_f16(vnegq_f16(vreinterpretq_f16_u16(vmvnq_u16(vdupq_n_u16((unsigned short)(0x27 + (argc > 99)))))));
  dump("mvni+fneg", &c, 8);
  return 0;
}
